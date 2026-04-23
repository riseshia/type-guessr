# frozen_string_literal: true

module TypeGuessr
  module Core
    module Converter
      # Method/class/module/constant definition methods for PrismConverter
      class PrismConverter
        private def convert_def(prism_node, context, module_function: false)
          def_context = context.fork(:method)
          def_context.current_method = prism_node.name.to_s
          def_context.in_singleton_method = prism_node.receiver.is_a?(Prism::SelfNode)

          # Convert parameters
          params = []
          if prism_node.parameters
            parameters_node = prism_node.parameters

            # Required parameters
            parameters_node.requireds&.each do |param|
              extract_param_nodes(param, :required, def_context).each do |param_node|
                params << param_node
              end
            end

            # Optional parameters
            parameters_node.optionals&.each do |param|
              default_node = convert(param.value, def_context)
              param_node = IR::ParamNode.new(param.name, :optional, default_node, [], convert_loc(param.location))
              params << param_node
              def_context.register_variable(param.name, param_node)
            end

            # Rest parameter (*args)
            if parameters_node.rest.is_a?(Prism::RestParameterNode)
              rest = parameters_node.rest
              param_node = IR::ParamNode.new(rest.name || :*, :rest, nil, [], convert_loc(rest.location))
              params << param_node
              def_context.register_variable(rest.name, param_node) if rest.name
            end

            # Required keyword parameters (name:)
            parameters_node.keywords&.each do |kw|
              case kw
              when Prism::RequiredKeywordParameterNode
                param_node = IR::ParamNode.new(kw.name, :keyword_required, nil, [], convert_loc(kw.location))
                params << param_node
                def_context.register_variable(kw.name, param_node)
              when Prism::OptionalKeywordParameterNode
                default_node = convert(kw.value, def_context)
                param_node = IR::ParamNode.new(kw.name, :keyword_optional, default_node, [], convert_loc(kw.location))
                params << param_node
                def_context.register_variable(kw.name, param_node)
              end
            end

            # Keyword rest parameter (**kwargs)
            if parameters_node.keyword_rest.is_a?(Prism::KeywordRestParameterNode)
              kwrest = parameters_node.keyword_rest
              param_node = IR::ParamNode.new(kwrest.name || :**, :keyword_rest, nil, [], convert_loc(kwrest.location))
              params << param_node
              def_context.register_variable(kwrest.name, param_node) if kwrest.name
            elsif parameters_node.keyword_rest.is_a?(Prism::ForwardingParameterNode)
              # Forwarding parameter (...)
              fwd = parameters_node.keyword_rest
              param_node = IR::ParamNode.new(:"...", :forwarding, nil, [], convert_loc(fwd.location))
              params << param_node
            end

            # Block parameter (&block)
            if parameters_node.block
              block = parameters_node.block
              param_node = IR::ParamNode.new(block.name || :&, :block, nil, [], convert_loc(block.location))
              params << param_node
              def_context.register_variable(block.name, param_node) if block.name
            end
          end

          # Convert method body - collect all body nodes
          body_nodes = []

          if prism_node.body.is_a?(Prism::StatementsNode)
            prism_node.body.body.each do |stmt|
              node = convert(stmt, def_context)
              body_nodes << node if node
            end
          elsif prism_node.body.is_a?(Prism::BeginNode)
            # Method with rescue/ensure block
            begin_node = prism_node.body
            body_nodes = extract_begin_body_nodes(begin_node, def_context)
          elsif prism_node.body
            node = convert(prism_node.body, def_context)
            body_nodes << node if node
          end

          # Collect all return points: explicit returns + implicit last expression
          return_node = compute_return_node(body_nodes, prism_node.name_loc)

          IR::DefNode.new(
            prism_node.name,
            def_context.current_class_name,
            params,
            return_node,
            body_nodes,
            [],
            convert_loc(prism_node.name_loc),
            prism_node.receiver.is_a?(Prism::SelfNode),
            module_function: module_function
          )
        end

        # Compute the return node for a method by collecting all return points
        # @param body_nodes [Array<IR::Node>] All nodes in the method body
        # @param loc [Prism::Location] Location for the MergeNode if needed
        # @return [IR::Node, nil] The return node (MergeNode if multiple returns)
        private def compute_return_node(body_nodes, loc)
          return nil if body_nodes.empty?

          # Collect all explicit returns from the body
          explicit_returns = collect_returns(body_nodes)

          # The implicit return is the last non-ReturnNode in body
          implicit_return = body_nodes.grep_v(IR::ReturnNode).last

          # Determine all return points
          return_points = explicit_returns.dup
          return_points << implicit_return if implicit_return && !last_node_returns?(body_nodes)

          case return_points.size
          when 0
            nil
          when 1
            return_points.first
          else
            IR::MergeNode.new(return_points, [], convert_loc(loc))
          end
        end

        # Collect all ReturnNode instances from body nodes (recursive)
        # Searches inside MergeNode branches to find nested returns from if/case
        # @param nodes [Array<IR::Node>] Nodes to search
        # @return [Array<IR::ReturnNode>] All explicit return nodes
        private def collect_returns(nodes)
          returns = []
          nodes.each do |node|
            case node
            when IR::ReturnNode
              returns << node
            when IR::MergeNode
              returns.concat(collect_returns(node.branches))
            when IR::OrNode
              returns.concat(collect_returns([node.lhs, node.rhs]))
            end
          end
          returns
        end

        # Check if the last node in body is a ReturnNode
        # @param body_nodes [Array<IR::Node>] Body nodes
        # @return [Boolean]
        private def last_node_returns?(body_nodes)
          body_nodes.last.is_a?(IR::ReturnNode)
        end

        private def convert_constant_read(prism_node, context)
          name = case prism_node
                 when Prism::ConstantReadNode
                   prism_node.name.to_s
                 when Prism::ConstantPathNode
                   prism_node.slice
                 else
                   prism_node.to_s
                 end

          IR::ConstantNode.new(name, context.lookup_constant(name), [], convert_loc(prism_node.location))
        end

        private def convert_constant_write(prism_node, context)
          value_node = convert(prism_node.value, context)
          context.register_constant(prism_node.name.to_s, value_node)
          IR::ConstantNode.new(prism_node.name.to_s, value_node, [], convert_loc(prism_node.location))
        end

        private def convert_class_or_module(prism_node, context)
          # Get class/module name first
          name = case prism_node.constant_path
                 when Prism::ConstantReadNode
                   prism_node.constant_path.name.to_s
                 when Prism::ConstantPathNode
                   prism_node.constant_path.slice
                 else
                   "Anonymous"
                 end

          # Create a new context for class/module scope with the full class path
          class_context = context.fork(:class)
          parent_path = context.current_class_name
          full_name = parent_path ? "#{parent_path}::#{name}" : name
          class_context.current_class = full_name

          # Collect all method definitions and nested classes from the body
          methods = []
          nested_classes = []
          if prism_node.body.is_a?(Prism::StatementsNode)
            prism_node.body.body.each do |stmt|
              if attr_accessor_call?(stmt)
                # attr_reader/attr_accessor/attr_writer DSL → 合成DefNodeを生成
                methods.concat(synthesize_attr_defs(stmt, class_context))
                next
              end

              node = convert(stmt, class_context)
              if node.is_a?(IR::DefNode)
                methods << node
              elsif node.is_a?(IR::ClassModuleNode)
                # Store nested class/module for separate indexing with proper scope
                nested_classes << node
              end
            end
          end
          # Store nested classes in methods array (RuntimeAdapter handles both types)
          methods.concat(nested_classes)

          IR::ClassModuleNode.new(name, methods, [], convert_loc(prism_node.constant_path&.location || prism_node.location))
        end

        ATTR_DSL_NAMES = %i[attr_reader attr_writer attr_accessor].freeze
        private_constant :ATTR_DSL_NAMES

        private def attr_accessor_call?(prism_node)
          return false unless prism_node.is_a?(Prism::CallNode)
          return false unless prism_node.receiver.nil?

          ATTR_DSL_NAMES.include?(prism_node.name)
        end

        # attr_reader/attr_writer/attr_accessor呼び出しから合成DefNodeを生成する
        # @return [Array<IR::DefNode>]
        private def synthesize_attr_defs(prism_node, context)
          dsl_name = prism_node.name
          args = prism_node.arguments&.arguments || []

          args.flat_map do |arg|
            attr_name = extract_attr_name(arg)
            next [] unless attr_name

            loc = convert_loc(arg.location)
            case dsl_name
            when :attr_reader
              [build_reader_def(attr_name, context.current_class_name, loc)]
            when :attr_writer
              [build_writer_def(attr_name, context.current_class_name, loc)]
            when :attr_accessor
              [
                build_reader_def(attr_name, context.current_class_name, loc),
                build_writer_def(attr_name, context.current_class_name, loc),
              ]
            end
          end
        end

        # 記号/文字列リテラル引数から属性名を取り出す
        # @return [Symbol, nil] シンボルで返す。リテラルでない場合はnil
        private def extract_attr_name(arg)
          case arg
          when Prism::SymbolNode
            arg.value&.to_sym
          when Prism::StringNode
            arg.unescaped.to_sym
          end
        end

        # attr_readerに対応する合成DefNode (引数なし、@ivarを返す)
        private def build_reader_def(attr_name, class_name, loc)
          ivar_name = :"@#{attr_name}"
          ivar_read = IR::InstanceVariableReadNode.new(ivar_name, class_name, nil, [], loc)
          IR::DefNode.new(attr_name, class_name, [], ivar_read, [ivar_read], [], loc, false)
        end

        # attr_writerに対応する合成DefNode (name= :引数を返す)
        private def build_writer_def(attr_name, class_name, loc)
          setter_name = :"#{attr_name}="
          param = IR::ParamNode.new(:value, :required, nil, [], loc)
          IR::DefNode.new(setter_name, class_name, [param], param, [param], [], loc, false)
        end

        private def convert_singleton_class(prism_node, context)
          # Create a new context for singleton class scope
          singleton_context = context.fork(:class)

          # Generate singleton class name in format: Parent::<Class:ParentName>
          # This matches the scope convention used by RuntimeAdapter and RubyIndexer
          parent_path = context.current_class_name || ""
          parent_name = IR.extract_last_name(parent_path) || "Object"
          singleton_suffix = "<Class:#{parent_name}>"
          singleton_name = parent_path.empty? ? singleton_suffix : "#{parent_path}::#{singleton_suffix}"
          singleton_context.current_class = singleton_name

          # Collect all method definitions from the body
          methods = []
          if prism_node.body.is_a?(Prism::StatementsNode)
            prism_node.body.body.each do |stmt|
              node = convert(stmt, singleton_context)
              methods << node if node.is_a?(IR::DefNode)
            end
          end

          IR::ClassModuleNode.new(singleton_name, methods, [], convert_loc(prism_node.location))
        end
      end
    end
  end
end

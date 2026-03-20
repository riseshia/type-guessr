# frozen_string_literal: true

# Core type system
require_relative "core/types"

# Node infrastructure
require_relative "core/node_key_generator"
require_relative "core/node_context_helper"
require_relative "core/ir"
require_relative "core/index"

# Registries
require_relative "core/registry"

# Converters
require_relative "core/converter"

# Inference
require_relative "core/inference"

# Utilities
require_relative "core/signature_builder"
require_relative "core/type_simplifier"
require_relative "core/type_serializer"
require_relative "core/cache"
require_relative "core/logger"

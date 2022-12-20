return function(options)
  local function eraseArguments()
      local i = 1
      while (options.arguments[i]) do
          options.arguments[i] = nil
          i = i + 1
      end
  end
  local handler = require 'busted.outputHandlers.base'()
  require 'busted.outputHandlers.junit'(options)
  eraseArguments()
  require 'busted.outputHandlers.utfTerminal'(options)
  return handler
end
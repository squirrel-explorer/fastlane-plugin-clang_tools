require 'fastlane_core/ui/ui'

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?('UI')

  module Helper
    class ClangToolsHelper
      def self.is_empty?(obj)
        if obj.nil?
          return true
        end

        case obj
        when String
          obj.empty?
        when Array, Hash
          obj.size.zero?
        else
          false
        end
      end

      def self.pick_non_empty(str1, str2)
        if !is_empty?(str1)
          str1
        elsif !is_empty?(str2)
          str2
        end
      end
    end
  end
end

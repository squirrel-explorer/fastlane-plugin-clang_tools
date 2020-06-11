require 'fastlane/action'
require_relative '../helper/clang_analyzer_helper'

module Fastlane
  module Actions
    class ClangAnalyzerAction < Action
      def self.run(params)
        # Parse CLI parameters
        analyze_params = prepare(params)
        if analyze_params.nil?
          puts('ERROR : Invalid parameters. Exiting ......')
          return
        end

        # Use xcodebuild to generate compilation database
        unless xcode_build(analyze_params)
          puts('ERROR : Failed to build project. Exiting ......')
          return
        end

        # Use clang analyzer to analyze the project
        unless clang_analyze(analyze_params)
          puts('ERROR : Failed to analyze project. Exiting ......')
          return
        end

        unless generate_summary(analyze_params)
          puts('ERROR : Failed to generate analysis summary. Exiting ......')
          return
        end
      end

      def self.prepare(params)
        if params.nil?
          analyze_params = nil
        else
          analyze_params = {}

          params.all_keys.each do |item|
            unless params[item].nil? || params[item].empty?
              analyze_params[item] = params[item]
            end
          end

          # The default output_format is 'plist-html'
          unless analyze_params.key?(:output_format)
            analyze_params[:output_format] = 'plist-html'
          end
          # For CI/CD convenience, this action only supports 'plist' or 'plist-html' as output_format
          unless analyze_params[:output_format].include?('plist')
            return nil
          end

          # The default output_dir is './static_analysis'
          unless analyze_params.key?(:output_dir)
            analyze_params[:output_dir] = './static_analysis'
          end
          FileUtils.mkdir_p(analyze_params[:output_dir]) unless File.exist?(analyze_params[:output_dir])
          analyze_params[:output_compile_commands] = "#{analyze_params[:output_dir]}/compile_commands.json"

          analyze_params[:output_report_dir] = "#{analyze_params[:output_dir]}/report-#{Time.new.strftime('%Y%m%d%H%M%S')}"
          FileUtils.mkdir_p(analyze_params[:output_report_dir]) unless File.exist?(analyze_params[:output_report_dir])

          analyze_params[:output_summary_file] = 'clang_analyzer_summary.xml'
        end

        analyze_params
      end

      def self.xcode_build(params)
        puts('Step : start xcodebuild ......')

        cmd_line = []

        # xcodebuild executive
        cmd_line << params.key?(:xcodebuild) ? params[:xcodebuild] : 'xcodebuild'

        # -project
        if params.key?(:project)
          cmd_line << "-project #{params[:project]}"
        else
          # -workspace
          if params.key?(:workspace)
            cmd_line << "-workspace #{params[:workspace]}"
          end

          # -scheme
          if params.key?(:scheme)
            cmd_line << "-scheme #{params[:scheme]}"
          end
        end

        # xcode configuration
        if params.key?(:configuration)
          cmd_line << "-configuration #{params[:configuration]}"
        end

        # build command
        cmd_line << 'clean'
        cmd_line << 'build'

        cmd_line << '|'

        # xcpretty executive
        cmd_line << params.key?(:xcpretty) ? params[:xcpretty] : 'xcpretty'

        cmd_line << '-r json-compilation-database'

        cmd_line << "--output #{params[:output_compile_commands]}"

        cmd = cmd_line.join(' ')
        puts("running : #{cmd}")

        stdout = `#{cmd}`
        # puts stdout

        ($?.to_i.zero? && stdout.index('clang: error: ').nil? && stdout.index('BUILD FAILED').nil?)
      end

      def self.clang_analyze(params)
        puts('Step : start clang analyzer ......')

        compile_cmds = File.read(params[:output_compile_commands])
        compile_cmds_json = JSON.parse(compile_cmds)

        compile_cmds_json.each do |cmd|
          analyzer_cmd = parse_compile_command(params, cmd)
          puts(analyzer_cmd)
          `#{analyzer_cmd}`
        end
      end

      def self.generate_summary(params)
        puts('Step : start generating analysis summary ......')

        plist_files = []
        Dir.foreach(params[:output_report_dir]) do |file|
          if File.extname(file) == '.plist'
            plist_files << file
          end
        end

        if plist_files.size.zero?
          puts('ERROR : Cannot find plist files. Other formats are not fully supported now.')
          return false
        end

        issues = []
        plist_files.each { |plist_file| parse_plist("#{params[:output_report_dir]}/#{plist_file}", issues) }

        ordered_issues = parse_issues(issues)
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.IssueList do
            ordered_issues.values.each do |issue_entry|
              issue_entry.each do |issue|
                xml.Issue do
                  xml.Checker(issue['checker'])
                  xml.Category(issue['category'])
                  xml.Type(issue['type'])
                  xml.Message(issue['message'])
                  xml.Source(issue['source_file'])
                  xml.Line(issue['line'])
                  xml.Col(issue['col'])
                  xml.Context(issue['context'])
                  xml.ContextKind(issue['context_kind'])
                  xml.HtmlAttachments do
                    issue['html_details'].each do |html|
                      xml.Attachment(html)
                    end
                  end
                end
              end
            end
          end
        end

        File.open("#{params[:output_report_dir]}/#{params[:output_summary_file]}", 'w') { |file| file.write(builder.to_xml) }

        true
      end

      def self.parse_compile_command(params, cmd_json)
        cmd = cmd_json['command']
        target_file = "#{cmd_json['directory']}/#{cmd_json['file']}"
        cmd_array = cmd.split(' ')

        analyzer_cmd_array = []

        # Use the specified clang if necessary
        analyzer_cmd_array << (params.key?(:clang) ? params[:clang] : cmd_array[0])
        cmd_array.shift

        subsequent = false
        cmd_array.each do |item|
          if subsequent
            subsequent = !item.start_with?('-')
          end

          if subsequent
            # Discard
          else
            if item.start_with?('-W') # warning
              # Discard '-W'
              subsequent = false
            elsif item.start_with?('-c', '-o', '-index-store-path')
              # Discard '-c', '-o', '-index-store-path'
              subsequent = true
            else
              analyzer_cmd_array << item
              subsequent = false
            end
          end
        end

        # Suppress all warnings
        analyzer_cmd_array << '-w'

        analyzer_cmd_array << '--analyze'

        # Set the output format of clang analyzer
        analyzer_cmd_array << "-Xclang -analyzer-output=#{params[:output_format]}"

        # Set the checker sets of clang analyzer
        analyzer_cmd_array << '-Xclang -analyzer-checker=core'
        analyzer_cmd_array << '-Xclang -analyzer-checker=cplusplus'
        analyzer_cmd_array << '-Xclang -analyzer-checker=deadcode'
        analyzer_cmd_array << '-Xclang -analyzer-checker=nullability'
        analyzer_cmd_array << '-Xclang -analyzer-checker=osx'
        analyzer_cmd_array << '-Xclang -analyzer-checker=security'
        analyzer_cmd_array << '-Xclang -analyzer-checker=unix'
        analyzer_cmd_array << '-Xclang -analyzer-checker=valist'
        analyzer_cmd_array << '-Xclang -analyzer-disable-checker=apiModeling'
        analyzer_cmd_array << '-Xclang -analyzer-disable-checker=optin'
        analyzer_cmd_array << '-Xclang -analyzer-disable-checker=alpha'

        # Set the target file to be analyzed
        analyzer_cmd_array << target_file

        # Set the output file
        report_file = File.basename(target_file, '.*')
        if params[:output_format].eql?('plist') || params[:output_format].eql?('plist-html')
          report_file += '.plist'
        elsif params[:output_format].eql?('html')
        end
        analyzer_cmd_array << "-o #{params[:output_report_dir]}/#{report_file}"

        analyzer_cmd_array.join(' ')
      end

      def self.parse_plist(plist_path, issues)
        plist = File.open(plist_path) { |f| Plist.parse_xml(f) }
        if plist.nil?
          return
        end

        # The corresponding source file of the plist file
        # Noted : the length of 'files' will always be 1 now
        plist_files = plist['files']
        if plist_files.nil? || plist_files.size.zero?
          return
        end

        plist_diagnostics = plist['diagnostics']
        if plist_diagnostics.nil? || plist_diagnostics.size.zero?
          return
        end

        # Analyze output diagnostics
        plist_diagnostics.each do |item|
          issue = {}
          issue['checker'] = item['check_name']
          issue['category'] = item['category']
          issue['type'] = item['type']
          issue['message'] = item['description']
          issue['source_file'] = plist_files[item['location']['file']]
          issue['line'] = item['location']['line']
          issue['col'] = item['location']['col']
          issue['context'] = item['issue_context']
          issue['context_kind'] = item['issue_context_kind']
          issue['html_details'] = item['HTMLDiagnostics_files']

          issues << issue
        end
      end

      def self.parse_issues(issues)
        ordered_issues = {}

        if issues.nil? || issues.size.zero?
          return ordered_issues
        end

        issues.each do |issue|
          issue_key = issue['checker']

          unless ordered_issues.key?(issue_key)
            ordered_issues[issue_key] = []
          end
          ordered_issues[issue_key] << issue
        end

        ordered_issues
      end

      def self.description
        'Analyze source codes with clang analyzer'
      end

      def self.authors
        ['squirrel-explorer']
      end

      def self.return_value
        # If your method provides a return value, you can describe here what it does
      end

      def self.details
        # Optional:
        'Run clang analyzer to analyze your source codes. We can help you find potential bugs or security risks in advance.'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :project,
                                       description: 'The xcode project',
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :workspace,
                                       description: 'The xcode workspace',
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :scheme,
                                       description: 'The scheme of xcode project',
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :configuration,
                                       description: 'The configuration of xcode project',
                                       optional: false,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :output_format,
                                       description: 'The output file format of static analysis',
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :output_dir,
                                       description: 'The output directory of static analysis',
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :xcodebuild,
                                       description: 'User-specified xcodebuild path',
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :xcpretty,
                                       description: 'User-specified xcpretty path',
                                       optional: true,
                                       type: String),
          FastlaneCore::ConfigItem.new(key: :clang,
                                       description: 'User-specified clang path',
                                       optional: true,
                                       type: String)
        ]
      end

      def self.is_supported?(platform)
        [:ios].include?(platform)
      end
    end
  end
end

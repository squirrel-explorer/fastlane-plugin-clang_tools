describe Fastlane::Actions::ClangAnalyzerAction do
  describe '#run' do
    it 'prints a message' do
      expect(Fastlane::UI).to receive(:message).with('The clang_tools plugin is working!')

      Fastlane::Actions::ClangAnalyzerAction.run(nil)
    end
  end
end

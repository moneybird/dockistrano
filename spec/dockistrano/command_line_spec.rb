require 'spec_helper'

describe Dockistrano::CommandLine do

  subject { described_class }

  context ".command_with_result" do
    it "executes the command and returns a string with the result" do
      expect(described_class.command_with_result("date")).to eq(`date`)
    end
  end

  context ".command_with_stream" do
    it "executes the command and returns a stream of output" do
      expect(Kernel).to receive(:system).with("date").and_return(true)
      expect(described_class.command_with_stream("date")).to be_true
    end
  end

  context ".command_with_interaction" do
    it "executes the command and returns a stream of output" do
      expect(Kernel).to receive(:exec).with("date").and_return(true)
      expect(described_class.command_with_interaction("date")).to be_true
    end
  end

end

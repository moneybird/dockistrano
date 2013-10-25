require 'spec_helper'

describe Dockistrano::Git do

  context ".repository_name" do
    let(:command) { double }

    it "returns the name from a ssh remote" do
      expect(Cocaine::CommandLine).to receive(:new).with("git config --get remote.origin.url").and_return(command)
      expect(command).to receive(:run).and_return("git@github.com:username/reponame-with-2.0.git")

      expect(described_class.repository_name).to eq("reponame-with-2.0")
    end

    it "returns the name from a ssh remote ending without .git" do
      expect(Cocaine::CommandLine).to receive(:new).with("git config --get remote.origin.url").and_return(command)
      expect(command).to receive(:run).and_return("git@github.com:username/reponame-with-2.0")

      expect(described_class.repository_name).to eq("reponame-with-2.0")
    end

    it "returns the name from a https remote" do
      expect(Cocaine::CommandLine).to receive(:new).with("git config --get remote.origin.url").and_return(command)
      expect(command).to receive(:run).and_return("https://github.com/username/reponame-with-2.0")

      expect(described_class.repository_name).to eq("reponame-with-2.0")
    end

    it "returns the name from a git:// url" do
      expect(Cocaine::CommandLine).to receive(:new).with("git config --get remote.origin.url").and_return(command)
      expect(command).to receive(:run).and_return("git://github.com/username/reponame-with-2.0.git")
      expect(described_class.repository_name).to eq("reponame-with-2.0")
    end

  end

  context ".branch" do
    let(:command) { double }
    it "returns the name of the branch" do
      expect(Cocaine::CommandLine).to receive(:new).with("git rev-parse --abbrev-ref HEAD").and_return(command)
      expect(command).to receive(:run).and_return("branch_name\n")

      expect(described_class.branch).to eq("branch_name")
    end

    it "returns the JANKY_BRANCH env variable when available" do
      ENV["JANKY_BRANCH"] = "feature/foobar"
      expect(described_class.branch).to eq("feature-foobar")
    end

  end


end

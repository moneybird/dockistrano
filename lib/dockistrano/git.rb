module Dockistrano

  class Git

    def self.repository_name
      git_url = Cocaine::CommandLine.new("git config --get remote.origin.url").run.strip

      if git_url =~ /^[A-z0-9]+@[A-z0-9.:\-]+\/([A-z0-9\-_\.]+)(\.git)?$/
        $1.gsub(/\.git$/, "")
      elsif git_url =~ /^(git|https?):\/\/[a-z\-\.]+\/[a-z\-\.]+\/([A-z0-9.\-\_]+)$/
        $2.gsub(/\.git$/, "")
      else
        raise "Unknown git url '#{git_url}'"
      end
    end

    def self.branch
      if ENV['JANKY_BRANCH']
        ENV['JANKY_BRANCH'].gsub("/", "-")
      else
        branch = Cocaine::CommandLine.new("git rev-parse --abbrev-ref HEAD").run.strip
        branch.gsub("/", "-")
      end
    end

  end
end

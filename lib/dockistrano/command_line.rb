module Dockistrano

  class CommandLine

    def self.command_with_result(command)
      debug(command)
      `#{command}`
    end

    def self.command_with_stream(command)
      debug(command)
      begin
        Kernel.system(command)
      rescue Interrupt
      end
    end

    def self.command_with_interaction(command)
      debug(command)
      Kernel.exec(command)
    end

    def self.debug(command)
      puts "$ #{command}" if false
    end

  end
end

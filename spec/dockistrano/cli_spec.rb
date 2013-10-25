require 'spec_helper'

describe Dockistrano::Cli do

  let(:service) { double(registry: "registry.provider.tld", image_name: "application", tag: "develop", volumes: [], backing_services: { "postgresql" => backing_service }, environment_variables: {}, newer_version_available?: false, stop: nil) }
  let(:backing_service) { double(full_image_name: "registry.provider.tld/postgresql:develop", image_name: "postgresql", running?: false, newer_version_available?: false, start: nil, stop: nil) }
  let(:hipache) { double }
  let(:output) { capture(:stdout) { described_class.start(command) } }

  before do
    allow(Dockistrano::Service).to receive(:factory).and_return(service)
  end

  context "doc status" do
    let(:command) { ["status"] }

    it "prints the DOCKISTRANO_ENVIRONMENT" do
      expect(output).to include("DOCKISTRANO_ENVIRONMENT: default")
    end

    it "prints the DOCKER_HOST_IP" do
      expect(output).to include("DOCKER_HOST_IP: 127.0.0.1")
    end

    it "prints the DOCKER_BINARY" do
      expect(output).to include("DOCKER_BINARY:")
      expect(output).to include("bin/docker")
    end

    it "prints the registry" do
      expect(output).to include("registry: #{service.registry}")
    end

    it "prints the name of the image" do
      expect(output).to include("image name: #{service.image_name}")
    end

    it "prints the tag" do
      expect(output).to include("tag: #{service.tag}")
    end

    it "lists all dependencies" do
      expect(output).to include(backing_service.full_image_name)
    end

    it "lists environment variables" do
      allow(service).to receive(:environment_variables).and_return({ "VARIABLE" => "value"} )
      expect(output).to include("VARIABLE=value")
    end

    it "lists the Hipache configuration" do
      allow(Dockistrano::Hipache).to receive(:new).with("127.0.0.1").and_return(hipache)
      allow(hipache).to receive(:status).and_return({ "somehostname.dev" => ["127.0.0.1:1000", "23.45.56.75:1234"] })
      expect(output).to include("somehostname.dev: 127.0.0.1:1000, 23.45.56.75:1234")
    end
  end

  context "doc build" do
    let(:command) { ["build"] }

    it "builds a container" do
      expect(service).to receive(:build).and_return(true)
      expect(service).to receive(:test).and_return(true)
      expect(service).to receive(:push).and_return(true)
      expect(output).to include("built")
      expect(output).to include("tests")
      expect(output).to include("pushed")
    end

    it "doesn't run the tests and push when building failed" do
      expect(service).to receive(:build).and_return(false)
      expect(service).to_not receive(:test)
      expect(service).to_not receive(:push)
      expect { output }.to raise_error(SystemExit)
    end

    it "doesn't push when tests failed" do
      expect(service).to receive(:build).and_return(true)
      expect(service).to receive(:test).and_return(false)
      expect(service).to_not receive(:push)
      expect { output }.to raise_error(SystemExit)
    end
  end

  context "doc pull" do
    let(:command) { ["pull"] }

    it "pulls a backing service when newer versions are available" do
      expect(backing_service).to receive(:newer_version_available?).and_return(true)
      expect(backing_service).to receive(:pull)
      expect(output).to include("Pulled")
    end

    it "doesn't pull a service when no new versions are available" do
      expect(backing_service).to receive(:newer_version_available?).and_return(false)
      expect(backing_service).to_not receive(:pull)
      expect(output).to include("Uptodate")
    end

    it "pulls the application container when newer versions are available" do
      expect(service).to receive(:newer_version_available?).and_return(true)
      expect(service).to receive(:pull)
      expect(output).to include("Pulled")
    end

    it "doesn't pull the application container when no newer versions are available" do
      expect(service).to receive(:newer_version_available?).and_return(false)
      expect(service).to_not receive(:pull)
      expect(output).to include("Uptodate")
    end
  end

  context "doc push" do
    it "pushes the current container" do
      expect(service).to receive(:push)
      described_class.start(["push"])
    end
  end

  context "doc start-services" do
    let(:command) { ["start-services"] }

    it "starts a backing service when it is not running" do
      expect(backing_service).to receive(:running?).and_return(false)
      expect(backing_service).to receive(:start)
      expect(output).to include("Started")
    end

    it "does nothing when a backing services is already running" do
      expect(backing_service).to receive(:running?).and_return(true)
      expect(backing_service).to_not receive(:start)
      expect(output).to include("Running")
    end
  end

  context "doc stop-all" do
    let(:command) { ["stop-all"] }

    it "stops the current container" do
      expect(service).to receive(:stop)
      expect(output).to include("Stopped")
    end

    it "stops all backing services" do
      expect(backing_service).to receive(:running?).and_return(true)
      expect(backing_service).to receive(:stop)
      expect(output).to include("Stopped")
    end
  end

  context "doc start" do
    let(:command) { ["start"] }

    it "starts the services when not running" do
      expect(service).to receive(:running?).and_return(false)
      expect(service).to receive(:start)
      expect(output).to include("Started")
    end

    it "doesn't start the services when already running" do
      expect(service).to receive(:running?).and_return(true)
      expect(service).to_not receive(:start)
      expect(output).to include("Running")
    end

    it "prints an error when environment variables are missing" do
      expect(service).to receive(:running?).and_return(false)
      expect(service).to receive(:start).and_raise(Dockistrano::Service::EnvironmentVariablesMissing.new("error message"))
      expect(output).to include("error message")
    end
  end

  context "doc stop" do
    let(:command) { ["stop"] }

    it "stops the current container" do
      expect(service).to receive(:stop)
      expect(output).to include("Stopped")
    end
  end

  context "doc stop ID" do
    let(:command) { ["stop", "123456789"] }

    it "stops the container with the id" do
      expect(Dockistrano::Docker).to receive(:stop).with("123456789")
      expect(output).to include("Stopped")
    end
  end

  context "doc restart" do
    let(:command) { ["restart"] }

    it "restarts the current container" do
      expect(service).to receive(:stop)
      expect(service).to receive(:start)
      expect(output).to include("Stopped")
      expect(output).to include("Started")
    end
  end

  context "doc exec COMMAND" do
    let(:command) { ["exec", "bin/rspec", "-t", "spec/models/my_model_spec.rb"] }

    it "executes the command in the container" do
      expect(service).to receive(:exec).with("bin/rspec -t spec/models/my_model_spec.rb", { "environment" => "default" })
      output
    end

    it "prints an error when environment variables are missing" do
      expect(service).to receive(:exec).and_raise(Dockistrano::Service::EnvironmentVariablesMissing.new("error message"))
      expect(output).to include("error message")
    end
  end

  context "doc console" do
    let(:command) { ["console"] }

    it "starts a bash console in the container" do
      expect(service).to receive(:console).with("/bin/bash", { "environment" => "default" })
      output
    end

    it "prints an error when environment variables are missing" do
      expect(service).to receive(:console).and_raise(Dockistrano::Service::EnvironmentVariablesMissing.new("error message"))
      expect(output).to include("error message")
    end
  end

  context "doc console COMMAND" do
    let(:command) { ["console", "bin/rails console"] }

    it "starts a console in the container" do
      expect(service).to receive(:console).with("bin/rails console", { "environment" => "default" })
      output
    end

    it "prints an error when environment variables are missing" do
      expect(service).to receive(:console).and_raise(Dockistrano::Service::EnvironmentVariablesMissing.new("error message"))
      expect(output).to include("error message")
    end
  end

  context "doc clean" do
    let(:command) { ["clean"] }

    it "cleans the Docker instance and service dependency cache" do
      expect(Dockistrano::Docker).to receive(:clean)
      expect(Dockistrano::ServiceDependency).to receive(:clear_cache)
      output
    end
  end

  context "doc logs" do
    let(:command) { ["logs"] }

    it "attaches to the containers output when the container is running" do
      expect(service).to receive(:running?).and_return(true)
      expect(service).to receive(:attach)
      expect(output).to include("Container application running, attaching to output")
    end

    it "prints the logs of the last run" do
      expect(service).to receive(:running?).and_return(false)
      expect(service).to receive(:logs)
      expect(output).to include("Container application stopped, printing logs of last run")
    end
  end

  context "doc logs NAME" do
    let(:command) { ["logs", "postgresql"] }

    it "attaches to the containers output when the container is running" do
      expect(backing_service).to receive(:running?).and_return(true)
      expect(backing_service).to receive(:attach)
      expect(output).to include("Container postgresql running, attaching to output")
    end

    it "prints the logs of the last run" do
      expect(backing_service).to receive(:running?).and_return(false)
      expect(backing_service).to receive(:logs)
      expect(output).to include("Container postgresql stopped, printing logs of last run")
    end
  end

  context "doc ALIAS ARGUMENTS" do
    let(:command) { ["rspec", "spec/models/my_model_spec.rb"] }

    it "executes aliases that are defined in the configuration" do
      allow(service).to receive(:config).and_return({ "aliases" => { "rspec" => "exec -e test bin/rspec" } })
      expect(Kernel).to receive(:exec).with("doc exec -e test bin/rspec spec/models/my_model_spec.rb")
      output
    end
  end

end

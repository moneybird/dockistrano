require 'spec_helper'

describe Dockistrano::Docker do

  subject { described_class }

  before do
    ENV["DOCKER_BINARY"] = "docker"
    ENV["DOCKER_HOST_IP"] = "127.0.0.1"
  end

  context ".docker_command" do
    it "returns a string that allows us to call docker" do
      ENV["DOCKER_BINARY"] = "/bin/docker"
      ENV["DOCKER_HOST_IP"] = "127.0.0.1"
      expect(subject.docker_command).to eq("/bin/docker -H 127.0.0.1")
    end

    it "raises an error when DOCKER_BINARY is not set" do
      ENV["DOCKER_BINARY"] = nil
      ENV["DOCKER_HOST_IP"] = "127.0.0.1"
      expect { subject.docker_command }.to raise_error(Dockistrano::Docker::EnvironmentVariableMissing, /DOCKER_BINARY/)
    end

    it "raises an error when DOCKER_BINARY is not set" do
      ENV["DOCKER_BINARY"] = "/bin/docker"
      ENV["DOCKER_HOST_IP"] = nil
      expect { subject.docker_command }.to raise_error(Dockistrano::Docker::EnvironmentVariableMissing, /DOCKER_HOST_IP/)
    end
  end

  context ".ps" do
    it "calls docker with the ps command" do
      expect(subject).to receive(:execute).with(["ps", {}])
      subject.ps
    end
  end

  context ".stop" do
    it "stops the container" do
      expect(subject).to receive(:execute).with(["stop", "123456789"])
      subject.stop("123456789")
    end
  end

  context ".run" do
    it "runs the default command when no command is given" do
      expect(subject).to receive(:execute).with(["run", {e: "VAR=value"}, "registry/image:tag"])
      subject.run("registry/image:tag", e: "VAR=value")
    end

    it "runs the default command when no command is given" do
      expect(subject).to receive(:execute).with(["run", {e: "VAR=value"}, "registry/image:tag", "echo 'foobar'"])
      subject.run("registry/image:tag", e: "VAR=value", command: "echo 'foobar'")
    end
  end

  context ".exec" do
    it "runs the default command when no command is given" do
      expect(subject).to receive(:execute).with(["run", {e: "VAR=value"}, "registry/image:tag"], :stream)
      subject.exec("registry/image:tag", e: "VAR=value")
    end

    it "runs the default command when no command is given" do
      expect(subject).to receive(:execute).with(["run", {e: "VAR=value"}, "registry/image:tag", "echo 'foobar'"], :stream)
      subject.exec("registry/image:tag", e: "VAR=value", command: "echo 'foobar'")
    end
  end

  context ".console" do
    it "runs the default command when no command is given" do
      expect(subject).to receive(:execute).with(["run", { "e" => "VAR=value", "t" => true, "i" => true }, "registry/image:tag"], :interaction)
      subject.console("registry/image:tag", "e" => "VAR=value")
    end

    it "runs the default command when no command is given" do
      expect(subject).to receive(:execute).with(["run", { "e" => "VAR=value", "t" => true, "i" => true}, "registry/image:tag", "echo 'foobar'"], :interaction)
      subject.console("registry/image:tag", "e" => "VAR=value", command: "echo 'foobar'")
    end
  end

  context ".execute" do
    it "calls docker and returns the result" do
      expect(Dockistrano::CommandLine).to receive(:command_with_result).with("docker -H 127.0.0.1 version")
      subject.execute(["version"])
    end

    it "adds options to the command" do
      expect(Dockistrano::CommandLine).to receive(:command_with_result).with("docker -H 127.0.0.1 version -a")
      subject.execute(["version", { a: true }])
    end

    it "adds array options to the command" do
      expect(Dockistrano::CommandLine).to receive(:command_with_result).with("docker -H 127.0.0.1 version -a b -a c")
      subject.execute(["version", { a: ["b", "c"] }])
    end

    it "calls docker and stream to stdout" do
      expect(Dockistrano::CommandLine).to receive(:command_with_stream).with("docker -H 127.0.0.1 version")
      subject.execute(["version"], :stream)
    end

    it "calls docker and takes over the console" do
      expect(Dockistrano::CommandLine).to receive(:command_with_interaction).with("docker -H 127.0.0.1 version")
      subject.execute(["version"], :interaction)
    end
  end

  context ".running_container_id" do
    it "returns the first id of a running container matching with the image name" do
      stub_request(:get, "http://127.0.0.1:4243/containers/json").to_return(status: 200, body: '[{"Id":"8e319853f561ba2c22de2ec9ff2584f99d091dd20cc5b393ab874631c6993a36","Image":"registry.dev.provider.net/provider-app-2.0:develop","Command":"bin/provider webserver","Created":1382449380,"Status":"Up 24 hours","Ports":[{"PrivatePort":3000,"PublicPort":49225,"Type":"tcp"}],"SizeRw":0,"SizeRootFs":0},
        {"Id":"107fc12c1c4b8e42091bd46e97c985d42c9e0d06506327e84f28fef585f9865a","Image":"registry.dev.provider.net/provider-app-2.0:develop","Command":"bin/provider worker","Created":1382449380,"Status":"Up 24 hours","Ports":[{"PrivatePort":3000,"PublicPort":49224,"Type":"tcp"}],"SizeRw":0,"SizeRootFs":0},
        {"Id":"066474c539231e445c636dd6ef2879e6a3e304cead10f78bd79e385b161cbdf5","Image":"registry.dev.provider.net/hipache:develop","Command":"supervisord -n","Created":1382447352,"Status":"Up 24 hours","Ports":[{"PrivatePort":80,"PublicPort":80,"Type":"tcp"},{"PrivatePort":6379,"PublicPort":16379,"Type":"tcp"}],"SizeRw":0,"SizeRootFs":0}]')

      expect(subject.running_container_id("registry.dev.provider.net/provider-app-2.0:develop")).to eq("8e319853f561ba2c22de2ec9ff2584f99d091dd20cc5b393ab874631c6993a36")
    end
  end

  context ".last_run_container_id" do
    it "returns the id of the previous run of the container" do
      stub_request(:get, "http://127.0.0.1:4243/containers/json?all=1").to_return(status: 200, body: '[{"Id":"8e319853f561ba2c22de2ec9ff2584f99d091dd20cc5b393ab874631c6993a36","Image":"registry.dev.provider.net/provider-app-2.0:develop","Command":"cat /dockistrano.yml","Created":1382449380,"Status":"Up 24 hours","Ports":[{"PrivatePort":3000,"PublicPort":49225,"Type":"tcp"}],"SizeRw":0,"SizeRootFs":0},
        {"Id":"107fc12c1c4b8e42091bd46e97c985d42c9e0d06506327e84f28fef585f9865a","Image":"registry.dev.provider.net/provider-app-2.0:develop","Command":"bin/provider worker","Created":1382449380,"Status":"Up 24 hours","Ports":[{"PrivatePort":3000,"PublicPort":49224,"Type":"tcp"}],"SizeRw":0,"SizeRootFs":0},
        {"Id":"066474c539231e445c636dd6ef2879e6a3e304cead10f78bd79e385b161cbdf5","Image":"registry.dev.provider.net/hipache:develop","Command":"supervisord -n","Created":1382447352,"Status":"Up 24 hours","Ports":[{"PrivatePort":80,"PublicPort":80,"Type":"tcp"},{"PrivatePort":6379,"PublicPort":16379,"Type":"tcp"}],"SizeRw":0,"SizeRootFs":0}]')

      expect(subject.last_run_container_id("registry.dev.provider.net/provider-app-2.0:develop")).to eq("107fc12c1c4b8e42091bd46e97c985d42c9e0d06506327e84f28fef585f9865a")
    end
  end

  context ".image_id" do
    it "returns the id of the image with the given name" do
      expect(subject).to receive(:inspect_image).and_return({ "id" => "123456789" })
      expect(subject.image_id("registry.dev/application:tag")).to eq("123456789")
    end
  end

  context ".inspect_image" do
    it "returns information about the image" do
      stub_request(:get, "http://127.0.0.1:4243/images/123456789/json").to_return({
        status: 200,
        body: '{"id":"49f387cc90f2d5b82ded91c239b6e583f8b955cb532912cc959b1d1289b3f8f1","parent":"7735e8f30a47f02aa46732e864879fad0fb0b74230f7695b6235d6faf766dcb2","created":"2013-10-21T16:03:17.191097983+02:00","container":"5c2c523d3561d205f5459925325890bbf8054010cd908f61feed3e76520dcf54","container_config":{},"docker_version":"0.6.3","config":{},"architecture":"x86_64","Size":12288}'
      })
      expect(subject.inspect_image("123456789")).to include('id')
    end

    it "raises an error when the image is not found" do
      stub_request(:get, "http://127.0.0.1:4243/images/123456789/json").to_return({
        status: 404,
        body: 'No such image: 123456789'
      })

      expect { subject.inspect_image("123456789") }.to raise_error(Dockistrano::Docker::ImageNotFound, /No such image: 123456789/)
    end
  end

  context ".build" do
    it "builds the container" do
      expect(subject).to receive(:execute).with(["build", {t: "full_image_name"}, "."], :stream)
      subject.build("full_image_name")
    end
  end

  context ".pull" do
    it "pulls the container with Docker" do
      expect(subject).to receive(:execute).with(["pull", { t: "tag" }, "full_image_name"])
      subject.pull("full_image_name", "tag")
    end
  end

  context ".push" do
    it "pushes the container with Docker" do
      expect(subject).to receive(:execute).with(["push", "full_image_name", "tag"], :stream)
      subject.push("full_image_name", "tag")
    end
  end

  context ".logs" do
    it "returns the logs for the container" do
      expect(subject).to receive(:execute).with(["logs", "72819312"], :stream)
      subject.logs("72819312")
    end
  end

  context ".attach" do
    it "attaches to the containers output" do
      expect(subject).to receive(:execute).with(["attach", "72819312"], :stream)
      subject.attach("72819312")
    end
  end

  context ".remove_container" do
    it "removes the container" do
      expect(subject).to receive(:execute).with(["rm", "application"])
      subject.remove_container("application")
    end
  end

  context ".inspect_container" do
    it "returns information about the container" do
      stub_request(:get, 'http://127.0.0.1:4243/containers/123456789/json').to_return({
        status: 200,
        body: '{"ID":"8e319853f561ba2c22de2ec9ff2584f99d091dd20cc5b393ab874631c6993a36","Created":"2013-10-22T15:43:00.213138644+02:00"}'
      })

      expect(subject.inspect_container("123456789")).to include("ID")
    end
  end

  context ".clean" do
    before do
      allow(Dockistrano::CommandLine).to receive(:command_with_stream)
      allow(subject).to receive(:docker_command).and_return("docker")
    end

    it "cleans images from the docker instance" do
      expect(Dockistrano::CommandLine).to receive(:command_with_stream).with("docker rmi $(docker images -a | grep \"^<none>\" | awk '{print $3}')")
      subject.clean
    end

    it "cleans containers from the docker instance" do
      expect(Dockistrano::CommandLine).to receive(:command_with_stream).with("docker rm $(docker ps -a -q)")
      subject.clean
    end
  end

  context ".stop_all_containers_from_image" do
    it "stops all containers from an image" do
      stub_request(:get, "http://127.0.0.1:4243/containers/json").to_return(status: 200, body: '[{"Id":"8e319853f561ba2c22de2ec9ff2584f99d091dd20cc5b393ab874631c6993a36","Image":"registry.dev.provider.net/provider-app-2.0:develop","Command":"bin/provider webserver","Created":1382449380,"Status":"Up 24 hours","Ports":[{"PrivatePort":3000,"PublicPort":49225,"Type":"tcp"}],"SizeRw":0,"SizeRootFs":0},
        {"Id":"107fc12c1c4b8e42091bd46e97c985d42c9e0d06506327e84f28fef585f9865a","Image":"registry.dev.provider.net/provider-app-2.0:develop","Command":"bin/provider worker","Created":1382449380,"Status":"Up 24 hours","Ports":[{"PrivatePort":3000,"PublicPort":49224,"Type":"tcp"}],"SizeRw":0,"SizeRootFs":0},
        {"Id":"066474c539231e445c636dd6ef2879e6a3e304cead10f78bd79e385b161cbdf5","Image":"registry.dev.provider.net/hipache:develop","Command":"supervisord -n","Created":1382447352,"Status":"Up 24 hours","Ports":[{"PrivatePort":80,"PublicPort":80,"Type":"tcp"},{"PrivatePort":6379,"PublicPort":16379,"Type":"tcp"}],"SizeRw":0,"SizeRootFs":0}]')

      expect(subject).to receive(:execute).with(["stop", "8e319853f561ba2c22de2ec9ff2584f99d091dd20cc5b393ab874631c6993a36"])
      expect(subject).to receive(:execute).with(["stop", "107fc12c1c4b8e42091bd46e97c985d42c9e0d06506327e84f28fef585f9865a"])

      subject.stop_all_containers_from_image("registry.dev.provider.net/provider-app-2.0:develop")
    end
  end

  context ".tags_for_image" do
    it "returns a list of tags for an image" do
      stub_request(:get, "http://127.0.0.1:4243/images/json").to_return({
        status: 200,
        body: '[{"Repository":"registry.provider.net/application","Tag":"develop"},{"Repository":"registry.provider.net/application","Tag":"latest"},{"Repository":"registry.provider.net/memcached","Tag":"develop"}]'
      })

      expect(subject.tags_for_image("registry.provider.net/application")).to eq(["develop", "latest"])
    end
  end

end

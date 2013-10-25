require 'spec_helper'

describe Dockistrano::Hipache do

  subject { described_class.new("127.0.0.1") }
  let(:redis) { double.as_null_object }

  before do
    allow(subject).to receive(:redis).and_return(redis)
  end

  context "#online?" do
    it "returns true when Hipache is online" do
      allow(redis).to receive(:ping).and_return(true)
      expect(subject.online?).to be_true
    end

    it "returns false when Hipache is offline" do
      allow(redis).to receive(:ping).and_raise(Redis::CannotConnectError)
      expect(subject.online?).to be_false
    end
  end

  context "#wait_for_online" do
    it "waits until Hipache is online" do
      expect(subject).to receive(:online?).and_return(false, false, false, true)
      expect(Kernel).to receive(:sleep).exactly(3).times
      subject.wait_for_online
    end

    it "waits for a maximum of 5 seconds" do
      expect(subject).to receive(:online?).and_return(false, false, false, false, false, false)
      expect(Kernel).to receive(:sleep).exactly(5).times
      subject.wait_for_online
    end
  end

  context "#register" do
    before do
      allow(subject).to receive(:wait_for_online)
      allow(subject).to receive(:online?).and_return(true)
    end

    it "waits for Hipache to be online" do
      expect(subject).to receive(:wait_for_online)
      subject.register("foobar", "application.dev", "33.33.33.33", "80")
    end

    it "removes any previously used addresses for the host" do
      expect(redis).to receive(:lrange).with("frontend:application.dev", 0, -1).and_return(["33.33.33.33:80"])
      expect(redis).to receive(:del).with("frontend:application.dev")
      subject.register("foobar", "application.dev", "33.33.33.33", "80")
    end

    it "creates a new host in Hipache" do
      expect(redis).to receive(:rpush).with("frontend:application.dev", "foobar")
      expect(redis).to receive(:rpush).with("frontend:application.dev", "http://33.33.33.33:80")
      subject.register("foobar", "application.dev", "33.33.33.33", "80")
    end
  end

  context "#unregister" do
    it "removes the ip address from Hipache" do
      expect(subject).to receive(:online?).and_return(true)
      expect(redis).to receive(:lrem).with("frontend:application.dev", 0, "http://33.33.33.33:80")
      subject.unregister("foobar", "application.dev", "33.33.33.33", "80")
    end
  end

  context "#status" do
    it "returns a hash with registered hosts in Hipache" do
      allow(subject).to receive(:online?).and_return(true)
      expect(redis).to receive(:keys).with("frontend:*").and_return(["frontend:application.dev"])
      expect(redis).to receive(:lrange).with("frontend:application.dev", 1, -1).and_return(["http://33.33.33.33:80"])
      expect(subject.status).to eq({
        "application.dev" => ["http://33.33.33.33:80"]
      })
    end
  end

end

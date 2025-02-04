require 'English'
require "test/unit"
require 'fileutils'

$LOAD_PATH << File.join(__dir__, '..', 'lib')
$LOAD_PATH << File.join(__dir__, '..', 'modules')

logdir = File.join(__dir__, '..', 'logs')
FileUtils.mkdir_p(logdir) unless File.exist?(logdir)

ENV['RACK_ENV'] = 'test'

# Make sure that tests put their temp files in a controlled location
# Clear temp file before each test run
ENV['TMPDIR'] = 'test/tmp'
FileUtils.rm_f Dir.glob 'test/tmp/*.tmp'

require "mocha/test_unit"
require "rack/test"
require 'timeout'
require 'webmock/test_unit'

require 'smart_proxy_for_testing'
require 'provider_interface_validation/dhcp_provider'

include DhcpProviderInterfaceValidation

def hash_symbols_to_strings(hash)
  Hash[hash.collect { |k, v| [k.to_s, v] }]
end

# Starts up a real smart proxy instance under WEBrick
# Use sparingly.  API tests should use rack-test etc.
module Proxy::IntegrationTestCase
  include Proxy::Log

  def setup
    WebMock.allow_net_connect!
  end

  def launch(protocol: 'https', plugins: [], settings: {})
    port = 0
    @settings = Proxy::Settings::Global.new(settings.merge("#{protocol}_port" => port))
    @t = Thread.new do
      launcher = Proxy::Launcher.new(@settings)
      app = launcher.public_send("#{protocol}_app", port, plugins)
      server = launcher.webrick_server(app.merge(AccessLog: [Logger.new('/dev/null')]), ['localhost'], port)
      # Read back the actual port it bound to
      @settings["#{protocol}_port"] = server.listeners[0].addr[1]
      server.start
    end
    Timeout.timeout(2) do
      sleep(0.1) until can_connect?('localhost', @settings["#{protocol}_port"])
    end
  end

  def can_connect?(host, port)
    return false if port == 0

    TCPSocket.new(host, port).close
    true
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
    false
  end

  def teardown
    WebMock.disable_net_connect!
    if @t
      Thread.kill(@t)
      @t.join(30)
    end
  end
end

class SmartProxyRootApiTestCase < Test::Unit::TestCase
  include Rack::Test::Methods

  def setup
    Proxy::LogBuffer::Buffer.instance.send(:reset)
  end

  def app
    Proxy::PluginInitializer.new(Proxy::Plugins.instance).initialize_plugins
    Proxy::RootV2Api.new
  end
end

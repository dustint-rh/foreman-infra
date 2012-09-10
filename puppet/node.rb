#! /usr/bin/env ruby

SETTINGS = {
  :url          => "http://localhost/",
  :puppetdir    => "/var/lib/puppet",
  :facts        => true,
  :storeconfigs => true,
  :timeout      => 3,
}

### Do not edit below this line

def url
  SETTINGS[:url] || raise("Must provide URL - please edit file")
end

def certname
  ARGV[0] || raise("Must provide certname as an argument")
end

def puppetdir
  SETTINGS[:puppetdir] || raise("Must provide puppet base directory - please edit file")
end

def stat_file
  FileUtils.mkdir_p "#{puppetdir}/yaml/foreman/"
  "#{puppetdir}/yaml/foreman/#{certname}.yaml"
end

def tsecs
  SETTINGS[:timeout] || 3
end

require 'net/http'
require 'net/https'
require 'fileutils'
require 'timeout'

def upload_facts
  # Temp file keeping the last run time
  last_run = File.exists?(stat_file) ? File.stat(stat_file).mtime.utc : Time.now - 365*24*60*60
  filename = "#{puppetdir}/yaml/facts/#{certname}.yaml"
  last_fact = File.stat(filename).mtime.utc
  if last_fact > last_run
    fact = File.read(filename)
    begin
      uri = URI.parse("#{url}/fact_values/create?format=yml")
      req = Net::HTTP::Post.new(uri.path)
      req.set_form_data('facts' => fact)
      res             = Net::HTTP.new(uri.host, uri.port)
      res.use_ssl     = uri.scheme == 'https'
      res.verify_mode = OpenSSL::SSL::VERIFY_NONE if res.use_ssl
      res.start { |http| http.request(req) }
    rescue => e
      raise "Could not send facts to Foreman: #{e}"
    end
  end
end

def cache result
  File.open(stat_file, 'w') {|f| f.write(result) }
end

def read_cache
  File.read(stat_file)
rescue => e
  raise "Unable to read from Cache file: #{e}"
end

def enc
  foreman_url      = "#{url}/node/#{certname}?format=yml"
  uri              = URI.parse(foreman_url)
  req              = Net::HTTP::Get.new(foreman_url)
  http             = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl     = uri.scheme == 'https'
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE if http.use_ssl
  res              = http.start { |http| http.request(req) }

  raise "Error retrieving node #{certname}: #{res.class}" unless res.code == "200"
  res.body
end

# Actual code starts here
begin
  # send facts to Foreman - optional uncomment 'upload_facts' to activate.
  # if you use this option below, make sure that you don't send facts to foreman via the rake task or push facts alternatives.
  #
  if ( SETTINGS[:facts] ) and not ( SETTINGS[:storeconfig] )
    upload_facts
  end
  #
  # query External node
  begin
    result = ""
    timeout(tsecs) do
      result = enc
      cache result
    end
  rescue TimeoutError, SocketError, Errno::EHOSTUNREACH
    # Read from cache, we got some sort of an error.
    result = read_cache
  ensure
    puts result
  end
rescue => e
  warn e
  exit 1
end

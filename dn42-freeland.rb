#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'netaddr'
require 'sinatra'
#require 'pry'

class Freeland
  def initialize
    # get prefix and inetnum json
    inetnum_uri = URI("http://109.24.208.244:8888/dn42-netblock-visu/registry-inetnums.json")
    inetnum_resp = Net::HTTP.get(inetnum_uri)
    @inetnums = JSON.parse inetnum_resp

    prefix_uri = URI("http://109.24.208.244:8888/dn42-netblock-visu/registry-prefixes.json")
    prefix_resp = Net::HTTP.get(prefix_uri)
    @prefixes = JSON.parse prefix_resp

    # this is the cake
    @dn42 = NetAddr::CIDR.create('172.22.0.0/15')

    # used address space
    @used_nets = @inetnums.map do |net,desc|
      net unless desc["policy"] == ["open"] or desc["policy"] == ["ask"]
    end.compact.find_all do |i|
      @dn42.contains?(i)
    end

    # open and ask for nets
    @love_nets = @inetnums.map do |net,desc|
      net if desc["policy"] == ["open"] or desc["policy"] == ["ask"]
    end.compact.find_all do |i|
      @dn42.contains?(i)
    end.sort.push("172.22.0.0/15")

    @freeland_list = @dn42.fill_in(@used_nets).delete_if { |net| @used_nets.include?(net) }
  end

  def get_parent_pref(prefix_list, freenet, meta, val)
    prefix_list.each do |prefix|
      if NetAddr::CIDR.create(prefix).contains?(freenet) or NetAddr::CIDR.create(prefix) == freenet
        return meta[prefix][val]
      end
    end
    return ["unknown"]
  end

  def generate_inetnums
    freeland_inetnums = {}
    @freeland_list.each do |prefix|
      freeland_inetnums[prefix] =
        {
        "status"=>["AVAILABLE"],
        "desc"=>["a somehow availabe network"],
        "inetnum"=>["#{NetAddr::CIDR.create(prefix).network}" + " - " + "#{NetAddr::CIDR.create(prefix).last}"],
        "policy"=>get_parent_pref(@love_nets, prefix, @inetnums, "policy"),
        "admin-c"=>get_parent_pref(@love_nets, prefix, @inetnums, "admin-c"),
        "mnt-by"=>get_parent_pref(@love_nets, prefix, @inetnums, "mnt-by"),
        "netname"=>[],
        "cidr"=>[prefix]
      }
    end
    @love_nets.each do |prefix|
      freeland_inetnums[prefix] = @inetnums[prefix]
    end

    JSON.pretty_generate(freeland_inetnums)
  end

  def check_prefix(subnet, network)
    NetAddr::CIDR.create(network).contains?(subnet) || NetAddr::CIDR.create(network) == subnet
  end

  def mark_display_none(prefix_obj)
    prefix_obj["children"].each do |child|
      child["display"] = "none"
      if not child["children"].empty?
        mark_display_none(child)
      end
    end
  end

  def stuff_prefix(prefix, networks)
    networks.each do |network|
      if check_prefix(prefix, network["prefix"])
        network.delete "display"
        stuff_prefix(prefix, network["children"])
      end
      if network["prefix"] == prefix
        network.delete "display"
      end
    end
  end

  def generate_prefixes
    mark_display_none(@prefixes)
    @freeland_list.each do |prefix|
      stuff_prefix(prefix, @prefixes["children"])
    end
    @prefixes["prefixes"] = @freeland_list.length

    JSON.pretty_generate(@prefixes)
  end
end

## for debuging
#freeland = Freeland.new
#freeland.generate_prefixes
#binding.pry

set :bind, '0.0.0.0'
set :port, 8000
set :public_folder, 'public'

get '/' do
  redirect 'index.html'
end

get '/free-inetnums.json' do
  freeland = Freeland.new
  freeland.generate_inetnums
end

get '/free-prefixes.json' do
  freeland = Freeland.new
  freeland.generate_prefixes
end


#
# Cookbook Name:: hostname
# Recipe:: default
#
# Copyright 2011, Maciej Pasternacki
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

require 'chef/util/file_edit'

fqdn = node.name


ruby_block "restart_chef" do
  block do
    if fork
      # i am the parent
      Chef::Log.info "Restarting chef..."
      exit 0
    else
      # i am the child
      sleep 0.1 until(Process.ppid() == 1)
      quoted_args = "'" << $*.join("' '") << "'" unless $*.empty?
        exec %Q{'#{$0}' #{quoted_args}}
      end
    end
    action :nothing
  end


  ohai "reload_ohai" do
    Chef::Log.debug "[LABS] ====> reloading OHAI"
    action :nothing
  end

  if fqdn
    fqdn =~ /^([^.]+)/
    hostname = $1


    if platform?("redhat", "centos", "amazon")

      ruby_block "edit sysconfig" do
        block do
          rc = Chef::Util::FileEdit.new("/etc/sysconfig/network")
          rc.search_file_replace_line(/^HOSTNAME=.*$/, "HOSTNAME=#{fqdn}")
          rc.write_file
          #notifies :run, resources(:execute => "set hostname"), :immediately
        end
      end

      execute "set hostname" do
        command "echo #{fqdn} > /proc/sys/kernel/hostname"
        action :run
        notifies :reload, resources(:ohai => "reload_ohai"), :immediately
        #notifies :create, "ruby_block[restart_chef]", :immediately
        #not_if { File.read('/proc/sys/kernel/hostname').chomp.eql?(node.fqdn) }
      end

    elsif platform?("ubuntu","debian")

      file '/etc/hostname' do
        content "#{hostname}\n"
        mode "0644"
      end

      if node[:hostname] != hostname
        execute "hostname #{hostname}"
      end

    end

    if node[:fqdn] != fqdn
      hosts_line = "#{node[:ipaddress]} #{fqdn} #{hostname}"
      ruby_block 'put_fqdn_in_hosts' do
        block do
          hosts = Chef::Util::FileEdit.new("/etc/hosts")
          if hosts.search_line(/^#{node[:ipaddress]}/)
            hosts.search_file_replace_line(/^#{node[:ipaddress]}/, hosts_line)
          else
            hosts.append_line(hosts_line)
          end
          hosts.write_file
        end
        not_if { File.read('/etc/hosts') =~ /^#{hosts_line}/ }
      end

    end

  else
    log "Please provide node name w/ desired hostname" do
      level :warn
    end
  end

  include_recipe "resolv"

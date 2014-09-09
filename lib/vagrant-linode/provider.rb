require 'vagrant-linode/actions'

module VagrantPlugins
  module Linode
    class Provider < Vagrant.plugin('2', :provider)

      # This class method caches status for all linodes within
      # the Linode account. A specific linode's status
      # may be refreshed by passing :refresh => true as an option.
      def self.linode(machine, opts = {})
        client = Helpers::ApiClient.new(machine).client

        # load status of linodes if it has not been done before
        if !@linodes
          @linodes = client.linode.list.each { |l| l.network = client.linode.ip.list :linodeid => l.linodeid }
	end

        if opts[:refresh] && machine.id
          # refresh the linode status for the given machine
          @linodes.delete_if { |d| d['linodeid'].to_s == machine.id }
          linode = client.linode.list(:linodeid => machine.id).first
	  linode.network = client.linode.ip.list :linodeid => linode['linodeid']
          @linodes << linode
        else
          # lookup linode status for the given machine
          linode = @linodes.find { |d| d['linodeid'].to_s == machine.id }
        end

        # if lookup by id failed, check for a linode with a matching name
        # and set the id to ensure vagrant stores locally
        # TODO allow the user to configure this behavior
        if !linode
          name = machine.config.vm.hostname || machine.name
          linode = @linodes.find { |d| d['label'] == name.to_s }
          machine.id = linode['linodeid'].to_s if linode
        end

        linode ||= {'status' => 0}
      end

      def initialize(machine)
        @machine = machine
      end

      def action(name)
        return Actions.send(name) if Actions.respond_to?(name)
        nil
      end

      # This method is called if the underying machine ID changes. Providers
      # can use this method to load in new data for the actual backing
      # machine or to realize that the machine is now gone (the ID can
      # become `nil`). No parameters are given, since the underlying machine
      # is simply the machine instance given to this object. And no
      # return value is necessary.
      def machine_id_changed
      end

      # This should return a hash of information that explains how to
      # SSH into the machine. If the machine is not at a point where
      # SSH is even possible, then `nil` should be returned.
      #
      # The general structure of this returned hash should be the
      # following:
      #
      #     {
      #       :host => "1.2.3.4",
      #       :port => "22",
      #       :username => "mitchellh",
      #       :private_key_path => "/path/to/my/key"
      #     }
      #
      # **Note:** Vagrant only supports private key based authenticatonion,
      # mainly for the reason that there is no easy way to exec into an
      # `ssh` prompt with a password, whereas we can pass a private key
      # via commandline.
      def ssh_info
        linode = Provider.linode(@machine)

        return nil if linode['status'] < 1

        public_network = linode.network.find { |network| network['ispublic'] == 1 }

        return {
          :host => public_network['ipaddress'],
          :port => '22',
          :username => 'root',
          :private_key_path => nil
        }
      end

      # This should return the state of the machine within this provider.
      # The state must be an instance of {MachineState}. Please read the
      # documentation of that class for more information.
      def state
        state = Provider.linode(@machine)['status']
        long = short = state.to_s
        Vagrant::MachineState.new(state, short, long)
      end
    end
  end
end

require 'puppet_x/voxpupuli/corosync/provider/crmsh'

Puppet::Type.type(:cs_property).provide(:crm, parent: PuppetX::Voxpupuli::Corosync::Provider::Crmsh) do
  desc 'Specific provider for a rather specific type since I currently have no plan to
        abstract corosync/pacemaker vs. keepalived. This provider will check the state
        of Corosync cluster configuration properties.'

  # Path to the crm binary for interacting with the cluster configuration.
  commands crm:           'crm'
  commands cibadmin:      'cibadmin'

  def self.instances
    block_until_ready

    instances = []

    cmd = [command(:crm), 'configure', 'show', 'xml']
    raw, = PuppetX::Voxpupuli::Corosync::Provider::Crmsh.run_command_in_cib(cmd)
    doc = REXML::Document.new(raw)

    cluster_property_set = doc.root.elements["configuration/crm_config/cluster_property_set[@id='cib-bootstrap-options']"]
    unless cluster_property_set.nil?
      cluster_property_set.each_element do |e|
        items = e.attributes
        property = { name: items['name'], value: items['value'] }

        property_instance = {
          name:       property[:name],
          ensure:     :present,
          value:      property[:value],
          provider:   name
        }
        instances << new(property_instance)
      end
    end
    instances
  end

  # Create just adds our resource to the property_hash and flush will take care
  # of actually doing the work.
  def create
    @property_hash = {
      name:   @resource[:name],
      ensure: :present,
      value:  @resource[:value]
    }
  end

  # Unlike create we actually immediately delete the item.
  def destroy
    debug('Revmoving cluster property')
    cibadmin('--scope', 'crm_config', '--delete', '--xpath', "//nvpair[@name='#{resource[:name]}']")
    @property_hash.clear
  end

  # Getters that obtains the first and second primitives and score in our
  # ordering definintion that have been populated by prefetch or instances
  # (depends on if your using puppet resource or not).
  def value
    @property_hash[:value]
  end

  # Our setters for the first and second primitives and score.  Setters are
  # used when the resource already exists so we just update the current value
  # in the property hash and doing this marks it to be flushed.
  def value=(should)
    @property_hash[:value] = should
  end

  # Flush is triggered on anything that has been detected as being
  # modified in the property_hash.  It generates a temporary file with
  # the updates that need to be made.  The temporary file is then used
  # as stdin for the crm command.
  def flush
    self.class.block_until_ready
    unless @property_hash.empty?
      # rubocop:enable Style/GuardClause
      # clear this on properties, in case it's set from a previous
      # run of a different corosync type
      cmd = [command(:crm), 'configure', 'property', '$id="cib-bootstrap-options"', "#{@property_hash[:name]}=#{@property_hash[:value]}"]
      PuppetX::Voxpupuli::Corosync::Provider::Crmsh.run_command_in_cib(cmd, @resource[:cib])
    end
  end
end

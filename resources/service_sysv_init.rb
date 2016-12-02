provides :hubot_service_sysvinit

provides :hubot_service, platform_family: 'suse'
provides :hubot_service, platform: 'amazon'

provides :hubot_service, platform: %w(redhat centos scientific oracle) do |node| # ~FC005
  node['platform_version'].to_f < 7.0
end

provides :hubot_service, platform: 'debian' do |node|
  node['platform_version'].to_i < 8
end

property :instance_name, String, name_property: true
property :install_path, String
property :hubot_user, kind_of: String, default: lazy { |r| "hubot_#{r.instance_name}" }
property :hubot_group, kind_of: String, default: nil # this is not used, but allows us swap providers without blowing up
property :env_vars, Array, default: [
  { 'CATALINA_PID' => '$CATALINA_BASE/bin/hubot.pid' }
]
property :sensitive, kind_of: [TrueClass, FalseClass], default: false

action :start do
  create_init

  service "hubot_#{new_resource.instance_name}" do
    provider platform_sysv_init_class
    supports restart: true, status: true
    action :start
  end
end

action :stop do
  service "hubot_#{new_resource.instance_name}" do
    provider platform_sysv_init_class
    supports status: true
    action :stop
    only_if { ::File.exist?("/etc/init.d/hubot_#{new_resource.instance_name}") }
  end
end

action :restart do
  service "hubot_#{new_resource.instance_name}" do
    provider platform_sysv_init_class
    supports status: true
    action :restart
  end
end

action :enable do
  create_init

  service "hubot_#{new_resource.instance_name}" do
    provider platform_sysv_init_class
    supports status: true
    action :enable
    only_if { ::File.exist?("/etc/init.d/hubot_#{new_resource.instance_name}") }
  end
end

action :disable do
  service "hubot_#{new_resource.instance_name}" do
    provider platform_sysv_init_class
    supports status: true
    action :disable
    only_if { ::File.exist?("/etc/init.d/hubot_#{new_resource.instance_name}") }
  end
end

action_class.class_eval do
  def create_init
    # set the CATALINA_BASE value unless the user has passed it
    ensure_catalina_base

    # define the lock dir for RHEL vs. debian
    platform_lock_dir = value_for_platform_family(
      %w(rhel fedora suse) => '/var/lock/subsys',
      'debian' => '/var/lock',
      'default' => '/var/lock'
    )

    # the init script will not run without redhat-lsb packages
    if platform_family?('rhel', 'fedora')
      if node['platform_version'].to_i < 6.0
        package 'redhat-lsb'
      else
        package 'redhat-lsb-core'
      end
    end

    template "#{derived_install_path}/bin/setenv.sh" do
      source 'setenv.erb'
      mode '0755'
      cookbook 'hubot'
      sensitive new_resource.sensitive
      notifies :restart, "service[hubot_#{new_resource.instance_name}]"
      variables(
        env_vars: new_resource.env_vars
      )
    end

    template "/etc/init.d/hubot_#{new_resource.instance_name}" do
      mode '0755'
      source 'init_sysv.erb'
      cookbook 'hubot'
      variables(
        user: new_resource.hubot_user,
        group: new_resource.hubot_group,
        lock_dir: platform_lock_dir,
        install_path: derived_install_path,
        instance_name: new_resource.instance_name
      )
    end
  end
end
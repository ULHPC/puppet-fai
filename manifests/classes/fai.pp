# File::      <tt>fai.pp</tt>
# Author::    Sebastien Varrette (Sebastien.Varrette@uni.lu)
# Copyright:: Copyright (c) 2012 Sebastien Varrette
# License::   GPLv3
#
# ------------------------------------------------------------------------------
# = Class: fai
#
# Configure and manage the Fully Automatic Installation (FAI) system
#
# == Parameters:
#
# $ensure:: *Default*: 'present'. Ensure the presence (or absence) of fai
# $allowed_clients:: *Default*: '*'. Specification of the hosts which can mount
#           this FAI config space directory via NFS.
# $configspacedir:: *Default*: '/srv/fai/config'.
#           Directory hosting the configuration space on the install server
# $configspace_provider:: *Default*: 'svn'. How to access the fai config space
# $configspace_url:: *Default*: 'svn.gforge.uni.lu/svn/ulclusters/'.
#           URL to access the config space
# $debmirror:: Hostname of the server that provides the Debian mirror via NFS
# $debmirror_exportdir:: *Default*: '/export/debmirror'. Export directory *on* the
#           debmirror server.
# $debmirror_mountdir:: *Default*: '/mnt/debmirror'. Local mount point where
#           the mirror will be mounted
# $debootstrap_suite:: *Default*: 'wheezy'. Suite (i.e.) distribution to be
#           used to generate the FAI NFSroot directory, see make-fai-nfsroot(8)
# $debootstrap_opts:: *Default*: '--exclude=dhcp-client,info --arch amd64'.
#           Options to be passed to debootstrap -- see make-fai-nfsroot(8).
# $deploynode_basename:: *Default*: 'node-'. Basename of the hostname of the
#           deployed nodes. It means nodes can be reach in the range
#           node-<minindex> .. node-<maxindex>
# $deploynode_minindex:: *Default*: 1. Minimal index of the deployed node.
# $deploynode_minindex:: *Default*: 1. Maximal index of the deployed node
# $ipmiuser:: *Default*: 'administrator'. The IPMI user to connect by IPMI to
#           the BMC card of the deployed nodes.
# $loguser:: *Default*: '' (i.e. disabled).
#           Account on the install server which saves all log-files and which
#           can change the kernel that is booted via network.
#           Define it, to enable it.
# $logproto:: *Default*: 'ssh'. Set protocol type for saving logs.
# $nfsrootdir:: *Default*: '/srv/fai/nfsroot'. Directory on the install server
#           where the nfsroot for FAI is created, approx size: 390MB.
# $nfsroot_hookdir:: *Default*: '/srv/fai/nfsroot-hooks'. Directory containing
#           shell scripts to be sourced at the end of make-fai-nfsroot for
#           additional configuration of the nfsroot.
# $rootpw_hash:: *Default*: '$1$kBnWcO.E$djxB128U7dMkrltJHPf6d1'.
#           The encrypted (with md5 or crypt) root password on all install
#           clients during installation process; used when log in via ssh;
#           Default password is: fai. You can create the encrypted password
#           using mkpasswd(1) and use the crypt(3) or md5 algorithm.
# $tftpdir:: *Default*: '/srv/tftp/fai/'. TFTP directory for FAI files
#
# == Actions:
#
# Install and configure FAI
#
# == Requires:
#
# n/a
#
# == Sample Usage:
#
#     import fai
#
# You can then specialize the various aspects of the configuration,
# for instance:
#
#         class { 'fai':
#             ensure => 'present'
#         }
#
# == Warnings
#
# /!\ Always respect the style guide available
# here[http://docs.puppetlabs.com/guides/style_guide]
#
#
# [Remember: No empty lines between comments and class definition]
#
class fai(
    $ensure                = $fai::params::ensure,
    $deploynode_basename   = 'node-',
    $deploynode_minindex   = 1,
    $deploynode_maxindex   = 1,
    $configspacedir        = $fai::params::configspacedir,
    $nfsrootdir            = $fai::params::nfsrootdir,
    $nfsroot_hookdir       = $fai::params::nfsroot_hookdir,
    $nfsroot_kernelversion = $fai::params::nfsroot_kernelversion,
    $tftpdir               = $fai::params::tftpdir,
    $loguser               = $fai::params::loguser,
    $logproto              = $fai::params::logproto,
    $configspace_provider  = $fai::params::configspace_provider,
    $configspace_url       = $fai::params::configspace_url,
    $debmirror             = $fai::params::debmirror,
    $debmirror_exportdir   = $fai::params::debmirror_exportdir,
    $debmirror_mountdir    = $fai::params::debmirror_mountdir,
    $debootstrap_suite     = $fai::params::debootstrap_suite,
    $debootstrap_opts      = $fai::params::debootstrap_opts,
    $rootpw_hash           = $fai::params::rootpw_hash,
    $ssh_identity          = $fai::params::ssh_identity,
    $allowed_clients       = $fai::params::allowed_clients,
    $ipmiuser              = $fai::params::ipmiuser,
    $use_backports         = $fai::params::use_backports,
    $initramfs_modules     = $fai::params::initramfs_modules
)
inherits fai::params
{
    info ("Configuring fai (with ensure = ${ensure})")

    if ! ($ensure in [ 'present', 'absent' ]) {
        fail("fai 'ensure' parameter must be set to either 'absent' or 'present'")
    }

    if ! ($configspace_provider in [ 'svn', 'git' ]) {
        fail("Unsupported provider '${configspace_provider} for the FAI configuration space")
    }

    case $::operatingsystem {
        debian, ubuntu:         { include fai::debian }
        default: {
            fail("Module $module_name is not supported on $operatingsystem")
        }
    }
}

# ------------------------------------------------------------------------------
# = Class: fai::common
#
# Base class to be inherited by the other fai classes
#
# Note: respect the Naming standard provided here[http://projects.puppetlabs.com/projects/puppet/wiki/Module_Standards]
class fai::common {

    include ipmitool
    # Load the variables used in this module. Check the fai-params.pp file
    require fai::params

    # Pre-requisite checks: ensure some services are set
    # TFTP server
    class { 'tftp::server':
        ensure   => "${fai::ensure}",
        data_dir => "${fai::tftpdir}",
        require  => File["${fai::tftpdir}"]
    }

    # # DHCP
    # # TODO: add a parameter to decide whether or not the fai class should also setup DHCP

    # NFS
    if (! defined( Class['nfs::server'] )) {
        class { 'nfs::server':
            ensure     => "${fai::ensure}",
            nb_servers => '64'
        }
    }
    # Exports the FAI config space and the NFSROOT by NFS
    nfs::server::export {
        [
         "${fai::configspacedir}",
         "${fai::nfsrootdir}"
         ]:
             ensure        => "${fai::ensure}",
             allowed_hosts => "${fai::allowed_clients}",
             require => [
                         Package['FAI'],
                         File["${fai::configspacedir}"],
                         File["${fai::nfsrootdir}"],
                         ]
    }

    # Ensure the local Debmirror is mounted
    exec { "mkdir -p ${fai::debmirror_mountdir}":
        path    => [ '/bin', '/usr/bin' ],
        unless  => "test -d ${fai::debmirror_mountdir}",
    }
    mount { "${fai::debmirror_mountdir}":
        ensure  => 'mounted',
        device  => "${fai::debmirror}:${fai::debmirror_exportdir}",
        atboot  => true,
        fstype  => "nfs",
        options => "async,defaults,auto,nfsvers=3,tcp,ro",
        require => Exec["mkdir -p ${fai::debmirror_mountdir}"]
    }

    package { 'FAI':
        name    => "${fai::params::packagename}",
        ensure  => "${fai::ensure}",
        require => Mount["${fai::debmirror_mountdir}"]
    }
    package { $fai::params::extra_packages:
        ensure => "${fai::ensure}",
        require => Mount["${fai::debmirror_mountdir}"]
    }

    # Configure kanif
    file { "/etc/kanif.conf":
        ensure  => "${fai::ensure}",
        owner   => 'root',
        group   => "${fai::params::admingroup}",
        mode    => '0644',
        source  => "puppet:///modules/fai/kanif.conf",
        require => Package['kanif']
    }

    # Create the group
    group { "${fai::params::admingroup}":
        ensure  => "${fai::ensure}",
    }
    # If sysadmin::login is configured, make it a member of this group
    if ( defined( Class['sysadmin']) ) {
        # adduser USER GROUP
        exec { "adduser ${sysadmin::login} ${fai::params::admingroup}":
            path    => "/usr/bin:/usr/sbin:/bin",
            require => Group["${fai::params::admingroup}"]
        }
    }

    # Prepare the binary tools
    if (! defined( File['/root/bin']) ) {
        file { "/root/bin":
            ensure => 'directory',
            owner  => 'root',
            group  => 'root',
            mode   => '0755',
        }
    }

    if $fai::ensure == 'present' {

        # Prepare le different directories
        #/var/log/fai
        file { "${fai::params::logdir}":
            ensure => 'directory',
            owner  => "${fai::params::logdir_owner}",
            group  => "${fai::params::logdir_group}",
            mode   => "${fai::params::logdir_mode}",
            require => Package['FAI'],
        }
        # /var/run/fai
        file { "${fai::params::piddir}":
            ensure => 'directory',
            owner  => "${fai::params::piddir_owner}",
            group  => "${fai::params::piddir_group}",
            mode   => "${fai::params::piddir_mode}",
            require => Package['FAI'],
        }
        # /etc/fai
        file { "${fai::params::configdir}":
            ensure => 'directory',
            owner  => "${fai::params::configdir_owner}",
            group  => "${fai::params::admingroup}",
            mode   => "${fai::params::configdir_mode}",
            require => [
                        Package['FAI'],
                        Group["${fai::params::admingroup}"]
                        ]
        }
        # /etc/fai/apt
        file { "${fai::params::aptdir}":
            ensure => 'directory',
            owner  => "${fai::params::configdir_owner}",
            group  => "${fai::params::admingroup}",
            mode   => "${fai::params::configdir_mode}",
            require => File["${fai::params::configdir}"]
        }
        # /etc/fai/apt/keys
        file { "${fai::params::aptkeysdir}":
            ensure => 'directory',
            owner  => "${fai::params::configdir_owner}",
            group  => "${fai::params::admingroup}",
            mode   => "${fai::params::configdir_mode}",
            recurse => true,
            recurselimit => 1,
            source  => "puppet:///modules/fai/apt/keys",
            require => File["${fai::params::aptdir}"]
        }



        # /etc/fai/nfsroot_hooks
        file { "${fai::params::nfsroot_hookdir}":
            ensure  => 'directory',
            owner   => "${fai::params::configdir_owner}",
            group   => "${fai::params::admingroup}",
            mode    => "${fai::params::configdir_mode}",
            # recurse => true,
            # recurselimit => 1,
            # source  => "puppet:///modules/fai/nfsroot-hooks",
            require => [
                        File["${fai::params::configdir}"],
                        File["${fai::params::nfsroot_configfile}"]
                        ]
        }
        # /srv/fai/config
        exec { "mkdir -p ${fai::configspacedir}":
            path    => [ '/bin', '/usr/bin' ],
            unless  => "test -d ${fai::configspacedir}",
        }
        file { "${fai::configspacedir}":
            ensure => 'directory',
            owner  => "${fai::params::configdir_owner}",
            group  => "${fai::params::admingroup}",
            mode   => "${fai::params::configdir_mode}",
            require => [
                        Package['FAI'],
                        Group["${fai::params::admingroup}"],
                        Exec["mkdir -p ${fai::configspacedir}"]
                        ]
        }
        # /srv/fai/nfsroot
        exec { "mkdir -p ${fai::nfsrootdir}":
            path    => [ '/bin', '/usr/bin' ],
            unless  => "test -d ${fai::nfsrootdir}",
        }
        file { "${fai::nfsrootdir}":
            ensure => 'directory',
            owner  => "${fai::params::configdir_owner}",
            group  => "${fai::params::admingroup}",
            mode   => "${fai::params::configdir_mode}",
            require => [
                        Package['FAI'],
                        Group["${fai::params::admingroup}"],
                        Exec["mkdir -p ${fai::nfsrootdir}"]
                        ]
        }
        # /srv/tftp/fai/
        if (! defined( File["${fai::tftpdir}"])) {
            file { "${fai::tftpdir}":
                ensure  => 'directory',
                owner   => "${fai::params::configdir_owner}",
                group   => "${fai::params::admingroup}",
                mode    => "${fai::params::configdir_mode}",
                require => [
                            Package['FAI'],
                            Group["${fai::params::admingroup}"]
                            ]
            }
        }

        # Now prepare the configuration space
        file { "/root/${fai::configspace_provider}":
            ensure => 'directory',
            owner  => "${fai::params::configdir_owner}",
            group  => "${fai::params::admingroup}",
            mode   => '0770'
        }

        $repo_path = gsub($fai::configspace_url, '.*\/', '')
        case $fai::configspace_provider {
            svn: {
                svn::checkout { "${repo_path}":
                    basedir => "/root/${fai::configspace_provider}",
                    source  => "${fai::configspace_url}",
                    require => File["/root/${fai::configspace_provider}"],
                    timeout => 60,
                }
            }
            git: {
                include git
                git::clone { "${repo_path}":
                    basedir => "/root/${fai::configspace_provider}",
                    source  => "${fai::configspace_url}",
                    branch  => 'devel',
                    require => File["/root/${fai::configspace_provider}"],
                }
            }
            default: { err ( "Unsupported provider for fai: '${fai::configspace_provider}'" ) }
        }

        # Configure FAI
        file { "${fai::params::configfile}":
            ensure  => "${fai::ensure}",
            owner   => "${fai::params::configfile_owner}",
            group   => "${fai::params::configfile_group}",
            mode    => "${fai::params::configfile_mode}",
            content => template("fai/fai.conf.erb"),
            require => File["${fai::params::configdir}"]
        }
        file { "${fai::params::make_nfsroot_configfile}":
            ensure  => "${fai::ensure}",
            owner   => "${fai::params::configfile_owner}",
            group   => "${fai::params::configfile_group}",
            mode    => "${fai::params::configfile_mode}",
            content => template("fai/make-fai-nfsroot.conf.erb"),
            require => File["${fai::params::configdir}"]
        }
        file { "${fai::params::nfsroot_configfile}":
            ensure  => "${fai::ensure}",
            owner   => "${fai::params::configfile_owner}",
            group   => "${fai::params::configfile_group}",
            mode    => "${fai::params::configfile_mode}",
            #source  => "puppet:///modules/fai/NFSROOT",
            content => template("fai/NFSROOT.erb"),
            require => File["${fai::params::configdir}"]
        }
        file { "${fai::params::apt_sources}":
            ensure  => "${fai::ensure}",
            owner   => "${fai::params::configfile_owner}",
            group   => "${fai::params::configfile_group}",
            mode    => "${fai::params::configfile_mode}",
            content => template("fai/apt/sources.list.erb"),
            require => File["${fai::params::configdir}"]
        }

        file { "${fai::params::nfsroot_hookdir}/10-blacklist-module":
            ensure  => "${fai::ensure}",
            owner   => "${fai::params::configdir_owner}",
            group   => "${fai::params::admingroup}",
            mode    => "${fai::params::hookfile_mode}",
            content => template("fai/nfsroot-hooks/blacklist-module.erb"),
            require => File["${fai::params::nfsroot_hookdir}"]
        }

        # Prepare the binary tools
        if ($site in [ 'gaia-cluster', 'chaos-cluster', 'nyx-cluster']) {
            $clustername = regsubst($site, '/-cluster/', '')
            file { "/root/bin/${clustername}-ipmi":
                ensure  => "${fai::ensure}",
                group   => "${fai::params::admingroup}",
                mode    => '0755',
                content => template("fai/ipmiwrapper.erb"),
                require => File["/root/bin"]
            }

            file { "/root/bin/${clustername}-update_fai":
                ensure  => "${fai::ensure}",
                group   => "${fai::params::admingroup}",
                mode    => '0755',
                content => template("fai/update-fai.erb"),
                require => File["/root/bin"]
            }

            file { "/root/bin/faiplay":
                ensure  => "${fai::ensure}",
                group   => "${fai::params::admingroup}",
                mode    => '0755',
                content => template("fai/faiplay.erb"),
                require => File["/root/bin"]
            }
            file { "/root/bin/${clustername}-fai":
                ensure  => 'link',
                target  => "/root/bin/faiplay",
                require => File["/root/bin/faiplay"]
            }

        }

    }
    else
    {
        # Here $fai::ensure is 'absent'

    }

}


# ------------------------------------------------------------------------------
# = Class: fai::debian
#
# Specialization class for Debian systems
class fai::debian inherits fai::common {

    # Version specific adaptations

    file { "${fai::params::nfsroot_hookdir}/30-patch-initrd":
        ensure  => "${fai::ensure}",
        owner   => "${fai::params::configdir_owner}",
        group   => "${fai::params::admingroup}",
        mode    => "${fai::params::hookfile_mode}",
        content => template("fai/nfsroot-hooks/patch-initrd.erb"),
        require => File["${fai::params::nfsroot_hookdir}"]
    }

    if ( $::lsbdistcodename == 'wheezy' ) {

        # Ugly / magical hack (enforced by fai-setup)
        # https://lists.uni-koeln.de/pipermail/linux-fai/2013-January/009899.html
        nfs::server::export { "/srv/nfs4":
            ensure  => "${fai::ensure}",
            content => "/srv/nfs4  ${ipaddress}/16(fsid=0,async,ro,no_subtree_check)\n",
            require => [
                        Package['FAI'],
                        File["${fai::configspacedir}"],
                        File["${fai::nfsrootdir}"],
                       ]
        }

        # Hack for the delta node (gaia-80)
        file { "${fai::params::nfsroot_hookdir}/20-download-mpt3sas":
            ensure  => "${fai::ensure}",
            owner   => "${fai::params::configdir_owner}",
            group   => "${fai::params::admingroup}",
            mode    => "${fai::params::hookfile_mode}",
            content => template("fai/nfsroot-hooks/download-mpt3sas.erb"),
            require => File["${fai::params::nfsroot_hookdir}"]
        }

        # Hack for the Moonshot nodes, requiring newer Mellanox driver than available in Debian7
        file { "${fai::params::nfsroot_hookdir}/21-download-mlx4":
            ensure  => "${fai::ensure}",
            owner   => "${fai::params::configdir_owner}",
            group   => "${fai::params::admingroup}",
            mode    => "${fai::params::hookfile_mode}",
            content => template("fai/nfsroot-hooks/download-mlx4.erb"),
            require => File["${fai::params::nfsroot_hookdir}"]
        }

        # Ugly hack, cf debian bug #731244
        # https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=731244
        exec { "sed -i 's/root=/root=${ipaddress}:/' /usr/sbin/fai-chboot":
            path    => "/usr/bin:/usr/sbin:/bin",
            unless  => "grep root=${ipaddress} /usr/sbin/fai-chboot",
            require => Package['FAI']
        }

        apt::source{"fai":
          type         => 'deb',
          uri          => 'http://fai-project.org/download',
          dist         => 'wheezy',
          components   => 'koeln',
          repo_key_url => 'http://fai-project.org/download/074BCDE4.asc'
        } -> Package['FAI']
    }
}


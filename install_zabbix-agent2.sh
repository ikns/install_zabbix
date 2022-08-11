#!/bin/sh
# 
# Установка и настройка агента мониторинга сервера (zabbix-agent2 6.0 LTS)
# Требуется запускать от root
# Работает на ОС:
# centos7,centos8,debian9,debian10,debian11,ubuntu18.04,ubuntu20.04,ubuntu22.04
#
# Лог работы скрипта /root/install_zabbix-agent2.log

RNAME="zabbix-agent2"

set -x

LOG_PIPE=/tmp/log.pipe.$$
mkfifo ${LOG_PIPE}
LOG_FILE=/root/install_zabbix-agent2.log
touch ${LOG_FILE}
chmod 600 ${LOG_FILE}

tee < ${LOG_PIPE} ${LOG_FILE} &

exec > ${LOG_PIPE}
exec 2> ${LOG_PIPE}

killjobs() {
    jops="$(jobs -p)"
    test -n "${jops}" && kill "${jops}" || :
}
trap killjobs INT TERM EXIT

echo
echo "=== Recipe ${RNAME} started at $(date) ==="
echo

HOME=/root
export HOME

set -x

###############################################################################

zabbix_fqdn=zabbix-ds.miran.tech

###############################################################################

if [ -f /etc/redhat-release ]; then
    OSNAME=centos
else
    OSNAME=debian
    export DEBIAN_FRONTEND="noninteractive"
fi

#zabbix agent 6.0 LTS
#CentOS
case $(< /etc/centos-release cut -f1 -d'.') in
    "CentOS Linux release 7" )
        rpm -Uvh https://repo.zabbix.com/zabbix/6.0/rhel/7/x86_64/zabbix-release-6.0-2.el7.noarch.rpm
        rm ./zabbix-release-6.0-2.el7.noarch.rpm
    ;;
    "CentOS Stream release 8" | "CentOS Linux release 8" )
        rpm -Uvh https://repo.zabbix.com/zabbix/6.0/rhel/8/x86_64/zabbix-release-6.0-2.el8.noarch.rpm
        rm ./zabbix-release-6.0-2.el8.noarch.rpm
    ;;
esac
#Debian/Ubuntu
case $(lsb_release -s -c) in
    "bullseye" ) # Debian 11 (Bullseye)
        wget https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-3+debian11_all.deb
        dpkg -i zabbix-release_6.0-3+debian11_all.deb && rm ./zabbix-release_6.0-3+debian11_all.deb
    ;;
    "buster" ) # Debian 10 (Buster)
        wget https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-3+debian10_all.deb
        dpkg -i zabbix-release_6.0-3+debian10_all.deb && rm ./zabbix-release_6.0-3+debian10_all.deb
    ;;
    "stretch" ) # Debian 9 (Stretch)
        wget https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-3+debian9_all.deb
        dpkg -i zabbix-release_6.0-3+debian9_all.deb && rm ./zabbix-release_6.0-3+debian9_all.deb
    ;;
    "jammy" ) # Ubuntu 22.04 (Jammy)
        wget https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.0-3+ubuntu22.04_all.deb
        dpkg -i zabbix-release_6.0-3+ubuntu22.04_all.deb && rm ./zabbix-release_6.0-3+ubuntu22.04_all.deb
    ;;
    "focal" ) # Ubuntu 20.04 (Focal)
        wget https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.0-3+ubuntu20.04_all.deb
        dpkg -i zabbix-release_6.0-3+ubuntu20.04_all.deb && rm ./zabbix-release_6.0-3+ubuntu20.04_all.deb
    ;;
    "bionic" ) # Ubuntu 18.04 (Bionic)
        wget https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.0-3+ubuntu18.04_all.deb
        dpkg -i zabbix-release_6.0-3+ubuntu18.04_all.deb && rm ./zabbix-release_6.0-3+ubuntu18.04_all.deb
        apt-get install -yq apt-transport-https
    ;;
esac

if [ "$OSNAME" = "debian" ]; then
    apt-get install -yq smartmontools sudo && apt-get update && apt-get install -yq zabbix-agent2
    path_egrep=$(which egrep)
elif [ "$OSNAME" = "centos" ]; then
    yum clean all && yum install -y smartmontools sudo zabbix-agent2
    path_egrep=$(which --skip-alias egrep)
    ip_zabbix=$(ping -4 -c2 $zabbix_fqdn | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | sort | uniq)
    firewall-cmd --new-zone=zabbix --permanent
    firewall-cmd --zone=zabbix --add-source="$ip_zabbix" --permanent
    firewall-cmd --zone=zabbix --add-port=10050/tcp --permanent
    firewall-cmd --reload
fi

path_smartctl=$(which smartctl)

echo 'zabbix  ALL=(ALL)NOPASSWD:   '"$path_smartctl"',/etc/zabbix/disks-discovery.pl,/etc/zabbix/AllDiskList.sh' >> /etc/sudoers

touch /etc/zabbix/AllDiskList.sh && chmod +x /etc/zabbix/AllDiskList.sh
touch /etc/zabbix/disks-discovery.pl && chmod +x /etc/zabbix/disks-discovery.pl

cat <<- EOF > /etc/zabbix/zabbix_agent2.conf
    Server=$zabbix_fqdn
    ServerActive=$zabbix_fqdn
    Hostname=DS-$(hostname -i)-$(hostname -s)-$RANDOM
    LogFileSize=10
    PidFile=/run/zabbix/zabbix_agent2.pid
    LogFile=/var/log/zabbix/zabbix_agent2.log
    ControlSocket=/tmp/agent.sock
    Include=/etc/zabbix/zabbix_agent2.d/*.conf
    Include=./zabbix_agent2.d/plugins.d/*.conf
EOF

cat <<- EOF > /etc/zabbix/AllDiskList.sh
    #!/bin/sh
    $path_smartctl --scan-open | cut -f1 -d '#' | while read line; do
        echo \$line \`$path_smartctl -i \$line | grep "Device Model:\|Model Number:\|Serial Number:\|Serial number:" | cut -d' ' -f3-\`
    done
EOF

cat <<- EOF > /etc/zabbix/zabbix_agent2.d/plugins.d/MiranParameter.conf
    UserParameter=AllDiskList,sudo /etc/zabbix/AllDiskList.sh
    UserParameter=mdraid, $path_egrep -c '\[.*_.*\]' /proc/mdstat 2>/dev/null; if [ \$? -eq 2 ] ; then echo "0" ; fi
    UserParameter=mdstat, cat /proc/mdstat 2>/dev/null || echo "no"
    UserParameter=uHDD.get[*],sudo $path_smartctl -i -H -A -l error -l background \$1 || true
    UserParameter=uSSD.get[*],sudo $path_smartctl -i -H -A -l error -l background \$1 || true
    UserParameter=uHDD.discovery[*],sudo /etc/zabbix/disks-discovery.pl \$1
    UserParameter=uSSD.discovery[*],sudo /etc/zabbix/disks-discovery.pl \$1
EOF

systemctl enable zabbix-agent2
systemctl restart zabbix-agent2

cat <<- "EOF" > /etc/zabbix/disks-discovery.pl
#!/usr/bin/perl
use warnings;
use strict;

#must be run as root
my $VERSION = 1.0;

#smartmontools
my $smartctl_cmd = "/usr/sbin/smartctl";
die "Unable to find smartctl. Check that smartmontools package is installed.\n" unless (-x $smartctl_cmd);
my @input_disks;
my @global_serials;
my @smart_disks;

if (@ARGV>0) {
    foreach my $disk_line (@ARGV) {
        $disk_line =~ s/_/ /g;
        my ($disk_name) = $disk_line =~ /(\/(.+?))(?:$|\s)/;
        my ($disk_args) = $disk_line =~ /(-d [A-Za-z0-9,\+]+)/;
        if (!defined($disk_args)) {
           $disk_args = '';
        }
        if ( $disk_name and defined($disk_args) ) {
            push @input_disks,
                {
                    disk_name => $disk_name,
                    disk_args => $disk_args
                };
        }
    }
}

foreach my $line (@{[
    `$smartctl_cmd --scan-open`,
    `$smartctl_cmd --scan-open -dnvme`
    ]}) {

    my ($disk_name) = $line =~ /(\/(.+?))(?:$|\s)/;
    my ($disk_args) = $line =~ /(-d [A-Za-z0-9,\+]+)/;

    if ( $disk_name and $disk_args ) {
        push @input_disks,
          {
            disk_name => $disk_name,
            disk_args => $disk_args
          };
    }

}

foreach my $disk (@input_disks) {

    my @output_arr;
    #initialize disk defaults:
    $disk->{disk_model}='';
    $disk->{disk_sn}='';
    $disk->{subdisk}=0;
    $disk->{disk_type}=2; # other

    if ( @output_arr = get_smart_disks($disk) ) {
        push @smart_disks, @output_arr;
    }
}

json_discovery( \@smart_disks );

sub get_smart_disks {
    my $disk = shift;
    my @disks;

    $disk->{smart_enabled} = 0;

    chomp( $disk->{disk_name} );
    chomp( $disk->{disk_args} );
    
    $disk->{disk_cmd} = $disk->{disk_name};
    if (length($disk->{disk_args}) > 0){
        $disk->{disk_cmd}.=q{ }.$disk->{disk_args};
        if ( $disk->{subdisk} == 1 and $disk->{disk_args} =~ /-d\s+[^,\s]+,(\S+)/) {
            $disk->{disk_name} .= " ($1)";
        }
    }

    my @smartctl_output = `$smartctl_cmd -i $disk->{disk_cmd} 2>&1`;
    foreach my $line (@smartctl_output) {
        #foreach my $line ($testline) {
        #print $line;
        if ( $line =~ /^(?:SMART.+?: +|Device supports SMART and is +)(.+)$/ ) {

            if ( $1 =~ /Enabled/ ) {
                $disk->{smart_enabled} = 1;
            }
            #if SMART is disabled then try to enable it (also offline tests etc)
            elsif ( $1 =~ /Disabled/ ) {
                foreach (`smartctl -s on -o on -S on $disk->{disk_cmd}`)
                {
                    if (/SMART Enabled/) { $disk->{smart_enabled} = 1; }
                }
            }
        }
    }
    my $vendor = '';
    my $product = '';
    foreach my $line (@smartctl_output) {
        # SAS: filter out non-disk devices (enclosure, cd/dvd)
        if ( $line =~ /^Device type: +(.+)$/ ) {
                if ( $1 ne "disk" ) {
                    return;
                }
        }
        # Areca: filter out empty slots
        if ( $line =~ /^Read Device Identity failed: empty IDENTIFY data/ ) {
            return;
        }
        
        if ( $line =~ /^serial number: +(.+)$/i ) {
                $disk->{disk_sn} = $1;
        }
        if ( $line =~ /^Device Model: +(.+)$/i ) {
                $disk->{disk_model} = $1;
        }

        #for NVMe disks and some ATA: Model Number:
        if ( $line =~ /^Model Number: +(.+)$/i ) {
                $disk->{disk_model} = $1;
        }
        #for SAS disks: Model = Vendor + Product
        elsif ( $line =~ /^Vendor: +(.+)$/ ) {
                $vendor = $1;
                $disk->{disk_model} = $vendor;
        }
        elsif ( $line =~ /^Product: +(.+)$/ ) {
                $product = $1;
                $disk->{disk_model} .= q{ }.$product;
        }
        
        if ( $line =~ /Rotation Rate: (.+)/i ) {

            if ( $1 =~ /Solid State Device/i ) {
                $disk->{disk_type} = 1;
            }
            elsif( $1 =~ /rpm/ ) {
                $disk->{disk_type} = 0;
            }
        }

        if ( $line =~ /Permission denied/ ) {

            warn $line;

        }
        elsif ( $disk->{subdisk} == 0 and $line =~ /failed: [A-zA-Z]+ devices connected, try '(-d [a-zA-Z0-9]+,)\[([0-9]+)\]'/) {

            foreach ( split //, $2 ) { 

                push @disks,
                  get_smart_disks(
                    {
                        disk_name => $disk->{disk_name},
                        disk_args => $1 . $_,
                        subdisk   => 1
                    }
                  );

            }
            return @disks;

        }
        
    }
    
    if ( $disk->{disk_name} =~ /nvme/ or $disk->{disk_args} =~ /nvme/) {
            $disk->{disk_type} = 1; # /dev/nvme is always SSD
            $disk->{smart_enabled} = 1;
    }

    if ( $disk->{disk_type} == 2) {
            foreach my $extended_line (`$smartctl_cmd -a $disk->{disk_cmd} 2>&1`){

                #search for Spin_Up_Time or Spin_Retry_Count
                if ($extended_line  =~ /Spin_/){
                    $disk->{disk_type} = 0;
                    last;
                }
                #search for SSD in uppercase
                elsif ($extended_line  =~ / SSD /){
                    $disk->{disk_type} = 1;
                    last;
                }
                #search for NVME
                elsif ($extended_line  =~ /NVMe/){
                    $disk->{disk_type} = 1;
                    last;
                }
                #search for 177 Wear Leveling Count(present only on SSD):
                elsif ($extended_line  =~ /177 Wear_Leveling/){
                    $disk->{disk_type} = 1;
                    last;
                }
                #search for 231 SSD_Life_Left (present only on SSD)
                elsif ($extended_line  =~ /231 SSD_Life_Left/){
                    $disk->{disk_type} = 1;
                    last;
                }
                #search for 233 Media_Wearout_Indicator (present only on SSD)
                elsif ($extended_line  =~ /233 Media_Wearout_/){
                    $disk->{disk_type} = 1;
                    last;
                }
            }
    }
    
    # push to global serials list
    if ($disk->{smart_enabled} == 1){
        #print "Serial number is ".$disk->{disk_sn}."\n";
        if ( grep /$disk->{disk_sn}/, @global_serials ) {
            # print "disk already exists skipping\n";
            return;
        }
        push @global_serials, $disk->{disk_sn};
    }

    push @disks, $disk;
    return @disks;

}

sub escape_json_string {
    my $string = shift;
    $string =~  s/(\\|")/\\$1/g;
    return $string;
}

sub json_discovery {
    my $disks = shift;

    my $first = 1;
    print "\t[\n";

    foreach my $disk ( @{$disks} ) {

        print ",\n" if not $first;
        $first = 0;
        print "\t\t{\n";
        print "\t\t\t\"{#DISKMODEL}\":\"".escape_json_string($disk->{disk_model})."\",\n";
        print "\t\t\t\"{#DISKSN}\":\"".escape_json_string($disk->{disk_sn})."\",\n";
        print "\t\t\t\"{#DISKNAME}\":\"".escape_json_string($disk->{disk_name})."\",\n";
        print "\t\t\t\"{#DISKCMD}\":\"".escape_json_string($disk->{disk_cmd})."\",\n";
        print "\t\t\t\"{#SMART_ENABLED}\":\"".$disk->{smart_enabled}."\",\n";
        print "\t\t\t\"{#DISKTYPE}\":\"".$disk->{disk_type}."\"\n";
        print "\t\t}";

    }
    print "\n\t]\n";
}
EOF

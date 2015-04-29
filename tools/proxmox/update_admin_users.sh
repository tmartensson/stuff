#!/bin/bash
# Script that add/removes admin users in proxmox based on information from /etc/group
#
# If you run this script without any args you will wipe all users present in /etc/pve/user.cfg
# To avoid that, you can add users in a comma-separated list that always should be present here:
# NOTE: You must manually set the password for PVE users.
#

# PAM Users:
always_present_pam="root"
# PVE Users:
always_present_pve="admin"

# Default email domain
email_domain="localhost"


grouplist=$(mktemp)

for args in "$@"
  do
    egrep -q "^$args:" /etc/group
      if [ "$?" != 0 ]; then
        echo "Group $args does NOT exist"
        rm $grouplist
        exit 1
      else
        echo $args >> $grouplist
      fi
done

groups=$(cat $grouplist)

# Use temporary files to store information
tmp_pam_users=$(mktemp)
tmp_pve_users=$(mktemp)
tmp_conf=$(mktemp)
tmp_group=$(mktemp)

# Add the "always present" users
echo "$always_present_pam" > $tmp_pam_users
echo "$always_present_pve" > $tmp_pve_users

# Get all members in the groups, store result in a tmp file
for group in $groups
  do
    egrep "$group:" /etc/group | awk -F":" '{ print $NF }' >> $tmp_pam_users
done

# We must add all members to a admin group, add the group and a placeholder as member.
echo "group:admin:_X_:admin group:" > $tmp_group

# Add all PAM users to file and add all users to the admin group stored in a separate file.
for user in $(cat $tmp_pam_users| sed 's/,/ /g')
  do
    echo "user:${user}@pam:1:0:::${user}@${$email_domain}::" >> $tmp_conf
    sed -i "s/_X_/${user}@pam,_X_/" $tmp_group
done

# Add all PVE users to file and add all users to the admin group stored in a separate file.
for user in $(cat $tmp_pve_users| sed 's/,/ /g')
  do
    echo "user:${user}@pve:1:0:::${user}@${$email_domain}::" >> $tmp_conf
    sed -i "s/_X_/${user}@pve,_X_/" $tmp_group
done

# Remove the placeholder from the group
sed -i "s/,_X_//" $tmp_group

# Add the group after we defined all users, will not work otherwise.
cat $tmp_group >> $tmp_conf

# Add the ACL that gives the admin group Administrator permissions.
echo "acl:1:/:@admin:Administrator:" >> $tmp_conf

# Copy the temporary configuration file to replace the current configuration.
cp $tmp_conf /etc/pve/user.cfg

# Clean up tmp files
rm $grouplist
rm $tmp_group
rm $tmp_conf
rm $tmp_pam_users
rm $tmp_pve_users


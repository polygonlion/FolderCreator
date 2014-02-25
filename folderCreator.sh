#!/bin/sh
#PATH=/bin:/usr/bin:/sbin:/usr/sbin export PATH

#####################################################################################################################
# FOLDER Creator v1.3 
# By Kevin Duffy
# Updated 02/17/2014 
#
# This tool is designed to read Active Directory to setup staff and student folders
#  1. Checks that the computer is bound to Active Directory
#  2. Checks the Application Folder, Log File and SQLite Database
#  3. Audits Staff Group
#  4. Creates new Staff folders
#  5. Checks Staff share permissions
#  6. Transfers Staff folders who fail audit
#  7. Audits Student Group
#  8. Creates new Student folders
#  9. Checks Student share permissions
# 10. Transfer Student folders who fail audit
# 11. Checks permissions on Student share
# 
# IMPORTANT ---> CRON REMINDER 
#
# This script is designed to be run as a cron job every night.
# To setup a cronjob, open the terminal and type "crontab -e" and paste the following line 
# 0 1 * * * /bin/bash/ /var/root/Scripts/FolderCreator/folderCreator.sh
######################################################################################################################





############################################
# SECTION ONE --> GLOBAL VARIABLES                
#
# This section contains all global variables                        
############################################
#####################
# TESTING VARIABLES #
#####################
#staffGroup="npm-staff"
#studentGroup="npm-students"
#fileserver="npm-xserver"
#building="npm"

####################
# SYSTEM VARIABLES #
####################
staffGroup=`hostname | cut -c 1-3`"-staff"
studentGroup=`hostname | cut -c 1-3`"-students"
fileserver=`hostname | cut -c 1-10`
building=`hostname | cut -c -3`
today=`date "+%Y-%m-%d"`
sqlDate=`date "+%m-%d-%Y"`

#################
# PATH VARIABLES#
#################
scriptPath="/var/root/Scripts/FolderCreator/"
logPath="/var/root/Scripts/FolderCreator/logs/"
logFile="/var/root/Scripts/FolderCreator/logs/$today.log"
sqlDatabase="/var/root/Scripts/FolderCreator/$building-database.sqlite"





#################################################################################
# SECTION TWO --> IDIOT CHECK
#
# This section checks to make sure that the computer is bound to Active Directory 
# It also makes sure that required folders, logs and sqlite database exists
#################################################################################

########################################
# Creates Application Folders If Missing
########################################
if [ ! -d "$scriptPath" ]; then
   mkdir -p "$scriptPath"
fi

if [ ! -d "$logPath" ]; then
   mkdir -p "$logPath"
fi


#############################
# Creates Log File If Missing
#############################
if [ -a "$logFile" ]; then
   echo "Log File is OK!"
  else
   /usr/bin/touch "$logFile"
fi
echo "-------------------------LOG START FOR $today-------------------------" >> "$logFile"


############################
# Creates Folders If Missing
############################
if [ ! -d /Volumes/Data/Staff ]; then
   echo "`date "+%H:%M:%S"` - Creating Staff Folder" >> "$logFile"
   mkdir -p /Volumes/Data/Staff
   chown -R admin:admin /Volumes/Data/Staff
   chmod -R 770 /Volumes/Data/Staff
fi

if [ ! -d /Volumes/Data/Transferred/Staff ]; then
   echo "`date "+%H:%M:%S"` - Creating Transferred Staff Folder" >> "$logFile"
   mkdir -p /Volumes/Data/Transferred/Staff
   chown -R admin:admin /Volumes/Data/Transferred/Staff
   chmod -R 770 /Volumes/Data/Transferred/Staff
fi

if [ ! -d /Volumes/Data/Students ]; then
   echo "`date "+%H:%M:%S"` - Creating Student Folder" >> "$logFile"
   mkdir -p /Volumes/Data/Students
   chown -R admin:admin /Volumes/Data/Students
   chmod -R 770 /Volumes/Data/Students
fi    

if [ ! -d /Volumes/Data/Transferred/Students ]; then
   echo "`date "+%H:%M:%S"` - Creating Transferred Student Folder" >> "$logFile"
   mkdir -p /Volumes/Data/Transferred/Students
   chown -R admin:admin /Volumes/Data/Transferred/Students
   chmod -R 770 /Volumes/Data/Transferred/Students
fi


##################################################
# Makes Sure Computer is Bound To Active Directory
##################################################
adCheck=`dscl /Active\ Directory/FSD/All\ Domains/ -read /Users/odbinder RecordName | cut -c 13-`

if [ $adCheck = "odbinder" ];
then  
    echo "`date "+%H:%M:%S"` - AD Check Passed" >> "$logFile"
else 
    echo "`date "+%H:%M:%S"` - Binding broken, sending warning email" >> "$logFile"
    mail -s "Folder Creator warning - $fileserver Not Bound To AD " kevin.duffy@k12northstar.org
    exit 0;
fi


####################################
# Creates SQLite Database If Missing
####################################
if [ -a $sqlDatabase ];
then
    echo "`date "+%H:%M:%S"` - SQL Database Check Passed" >> "$logFile"
else
    echo "`date "+%H:%M:%S"` - SQL Database Missing. Creating Now" >> "$logFile"
    /usr/bin/sqlite3 "$sqlDatabase" "CREATE TABLE staff (userID string, userName string, adGroup string, adHome string, localHome string, localHomeCreationDate string, permissionsCheckDate string, transferHome string, transferDate string, transferCountdown string, emailAddress string, emailWarningFirst string, emailWarningSecond string, emailWorkOrderSystem string, lastChecked string);"
    /usr/bin/sqlite3 "$sqlDatabase" "CREATE TABLE students (userID string, userName string, graduationYear string, adGroup string, adHome string, localHome string, localHomeCreationDate string, permissionsCheckDate string, transferHome string, transferDate string, transferCountdown string, lastChecked string);"
fi





#############################################################################################################################################################################################
#############################################################################################################################################################################################
#############################################################################################################################################################################################
#
#                                                                                              STAFF SECTION
#
#############################################################################################################################################################################################
#############################################################################################################################################################################################
#############################################################################################################################################################################################





#######################################################################
# SECTION THREE --> STAFF AUDIT
#
# Audits building staff group and adds all new users to sqlite database
#######################################################################
echo "-------------------------STAFF AUDIT--------------------------------------" >> "$logFile"
dscl /Active\ Directory/FSD/All\ Domains/ -read /Groups/"$staffGroup" GroupMembership | awk 'gsub(/FSD/, "\n")' | grep f[0-9] | sed 's/[!@#\$%^&*()]//g' >> "$scriptPath"staffList.txt


##########################################
# Checks to see if the user already exists
##########################################
while read line; do
      userID="$line"
      quickCheck=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT userID FROM staff WHERE userID='$userID';"`
      if [ "$quickCheck" != "$userID" ]; then
          echo "$userID" >> "$scriptPath"staffListFiltered.txt
      else
          echo "$userID" >> "$scriptPath"staffNameCheck.txt
          /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET lastChecked='$sqlDate' WHERE userID='$userID';"
      fi      
      
done < "$scriptPath"staffList.txt
rm -rf "$scriptPath"staffList.txt


###########################
# Adds new staff accounts
###########################
while read line; do
      userID="$line"
      serverName=`dscl /Active\ Directory/FSD/All\ Domains/ -read /Users/"$userID" SMBHome | grep -o [a-z][a-z][a-z]-xserve`
      userRealName=`dscl /Active\ Directory/FSD/All\ Domains/ -read /Users/"$userID" RealName | grep "," | cut -c 2-`
      smbHomeRaw=`dscl /Active\ Directory/FSD/All\ Domains/ -read /Users/"$userID" SMBHome | grep "$building-" | cut -c 2-`
      smbHomeProcessed=$(echo "$smbHomeRaw" | sed 's:\\:/:g')
      localHome=$(echo "$smbHomeProcessed" | sed 's://'$serverName':/Volumes/Data:g')
      transferHome=$(echo "$smbHomeProcessed" | sed 's://'$serverName':/Volumes/Data/Transferred:g')     
      emailAddress=`dscl /Active\ Directory/FSD/All\ Domains/ -read /Users/"$userID" EMailAddress | cut -c 15-`
              
      apostropheNameCheck=$(echo "$userRealName" | grep "'")
      apostropheSMBCheck=$(echo "$smbHomeRaw" | grep "'")
      apostropheEmailCheck=$(echo "$emailAddress" | grep "'")    
 
      ####################################################
      # Checks to see if there is a apostrophe in the name
      ####################################################
      if [ "$userRealName" = "$apostropheNameCheck" ];
         then
             userRealName=$(echo "$userRealName" | sed "s/'/\''/g")  
             echo "apostrophe name is $userRealName"          
             /usr/bin/sqlite3 "$sqlDatabase" "INSERT into staff (userID, userName, adGroup, lastChecked) values ('$userID', '$userRealName', '$staffGroup', '$sqlDate');"
             echo "$userRealName contains apostrophe"
             echo "`date "+%H:%M:%S"` - ADDING TO SQLITE DATABASE: $userID AKA $userRealName" >> "$logFile"         
         else
             
             /usr/bin/sqlite3 "$sqlDatabase" "INSERT into staff (userID, userName, adGroup, lastChecked) values ('$userID', '$userRealName', '$staffGroup', '$sqlDate');"
             echo "`date "+%H:%M:%S"` - ADDING TO SQLITE DATABASE: $userID AKA $userRealName" >> "$logFile"     
      fi

      ########################################################
      # Checks to see if there is a apostrophe in the smb path
      ########################################################      
      if [ "$smbHomeRaw" = "$apostropheSMBCheck" ];
         then
             smbHomeProcessed=$(echo "$smbHomeProcessed" | sed "s/'/\''/g")
             localHome=$(echo "$localHome" | sed "s/'/\''/g")
             transferHome=$(echo "$transferHome" | sed "s/'/\''/g")
      
             /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET adHome='$smbHomeProcessed', localHome='$localHome', transferHome='$transferHome' WHERE userID='$userID';"    
         else
             /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET adHome='$smbHomeProcessed', localHome='$localHome', transferHome='$transferHome' WHERE userID='$userID';"            
      fi        

      #########################################################
      # Checks to see if there is a apostrophe in Email Address
      #########################################################
      if [ "$emailAddress" = "$apostropheEmailCheck" ];
         then
             emailAddress=$(echo "$emailAddress" | sed "s/'/\''/g")
             /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET emailAddress='$emailAddress' WHERE userID='$userID';"    
         else
             /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET emailAddress='$emailAddress' WHERE userID='$userID';"    
      fi
         
      ######################
      # Does Not Belong Here
      ######################
      if [ -z "$transferHome" -a "$transferHome"!=" " ];
      then
         /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET adHome='CHARLATAN', localHome='CHARLATAN', localHomeCreationDate='CHARLATAN', permissionsCheckDate='CHARLATAN', transferHome='CHARLATAN', transferDate='CHARLATAN',transferCountdown='CHARLATAN' WHERE userID='$userID';"
         echo "`date "+%H:%M:%S"` - SPECIAL USER: $userID AKA $userRealName does not belong on this server" >> "$logFile" 
      fi   
             
done < "$scriptPath"staffListFiltered.txt
rm -rf "$scriptPath"staffListFiltered.txt





###############################################################################################################
# SECTION FOUR --> NAME UPDATE
#
# This section updates the name  and smb path of users that have been previously entered in the sqlite database
###############################################################################################################
echo "-------------------------UPDATING STAFF INFORMATION-----------------------" >> "$logFile"
while read line; do
      userID="$line"
      sqlLocalHome=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT adHome FROM staff WHERE userid='$userID';"`      

      if [ "$sqlLocalHome" != "CHARLATAN" ];
         then
             echo "$userID" >> "$scriptPath"staffNameCheckFiltered.txt         
      fi

done < "$scriptPath"staffNameCheck.txt
rm -rf "$scriptPath"staffNameCheck.txt



while read line; do
      userID="$line"
      serverName=`dscl /Active\ Directory/FSD/All\ Domains/ -read /Users/"$userID" SMBHome | grep -o [a-z][a-z][a-z]-xserve`
      userRealName=`dscl /Active\ Directory/FSD/All\ Domains/ -read /Users/"$userID" RealName | grep "," | cut -c 2-`
      smbHomeRaw=`dscl /Active\ Directory/FSD/All\ Domains/ -read /Users/"$userID" SMBHome | grep "$building-" | cut -c 2-`
      smbHomeProcessed=$(echo "$smbHomeRaw" | sed 's:\\:/:g')
      localHome=$(echo "$smbHomeProcessed" | sed 's://'$serverName':/Volumes/Data:g')
      transferHome=$(echo "$smbHomeProcessed" | sed 's://'$serverName':/Volumes/Data/Transferred:g')     
      emailAddress=`dscl /Active\ Directory/FSD/All\ Domains/ -read /Users/"$userID" EMailAddress | cut -c 15-`

      sqlLocalHome=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT adHome FROM staff WHERE userid='$userID';"`      

      if [ "$smbHomeProcessed" != "$sqlLocalHome" ];
         then
             sqlOldHome=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT localHome FROM staff WHERE userid='$userID';"`
             
             apostropheNameCheck=$(echo "$userRealName" | grep "'")
             apostropheSMBCheck=$(echo "$smbHomeRaw" | grep "'")
             apostropheEmailCheck=$(echo "$emailAddress" | grep "'")    
 
             ####################################################
             # Checks to see if there is a apostrophe in the name
             ####################################################
             if [ "$userRealName" = "$apostropheNameCheck" ];
                then
                    userRealName=$(echo "$userRealName" | sed "s/'/\''/g")  
                    echo "apostrophe name is $userRealName"          
                    /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET userName='$userRealName' WHERE userID='$userID';"
                    echo "$userRealName contains apostrophe"
                else            
                    /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET userName='$userRealName' WHERE userID='$userID';"
             fi

             ########################################################
             # Checks to see if there is a apostrophe in the smb path
             ########################################################      
             if [ "$smbHomeRaw" = "$apostropheSMBCheck" ];
                then
                    smbHomeProcessed=$(echo "$smbHomeProcessed" | sed "s/'/\''/g")
                    localHome=$(echo "$localHome" | sed "s/'/\''/g")
                    transferHome=$(echo "$transferHome" | sed "s/'/\''/g")
      
                    /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET adHome='$smbHomeProcessed', localHome='$localHome', transferHome='$transferHome' WHERE userID='$userID';"   
                else
                    /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET adHome='$smbHomeProcessed', localHome='$localHome', transferHome='$transferHome' WHERE userID='$userID';"            
             fi        

             #########################################################
             # Checks to see if there is a apostrophe in Email Address
             #########################################################
             if [ "$emailAddress" = "$apostropheEmailCheck" ];
                then
                    emailAddress=$(echo "$emailAddress" | sed "s/'/\''/g")
                    /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET emailAddress='$emailAddress' WHERE userID='$userID';"    
                else
                    /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET emailAddress='$emailAddress' WHERE userID='$userID';"    
             fi
                                
             echo "`date "+%H:%M:%S"` - RECORD UPDATED: $userID aka $userRealName" >> "$logFile"
             
             /bin/mv "$sqlOldHome" "$localHome"
             echo "$sqlOldHome $localHome"            
      fi
             
done < "$scriptPath"staffNameCheckFiltered.txt
rm -rf "$scriptPath"staffNameCheckFiltered.txt





####################################################################################
# SECTION FIVE --> FOLDER CREATION
#
# This section creates folders for all staff that do not have a folder creation date
####################################################################################
echo "-------------------------STAFF FOLDER CREATION----------------------------" >> "$logFile"
/usr/bin/sqlite3 "$sqlDatabase" "SELECT userID FROM staff WHERE localHomeCreationDate IS NULL;" >> "$scriptPath"stafffolderList.txt
while read line; do
      userID="$line"
      sqlLocalHome=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT localHome FROM staff WHERE userid='$userID';"`
           
      /bin/echo "`date "+%H:%M:%S"` - CREATING FOLDER: $userID" >> "$logFile" 
      /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET localHomeCreationDate='$sqlDate' WHERE userID='$userID';"
      /bin/mkdir -p "$sqlLocalHome"
      /usr/sbin/chown -R "$userID":admin "$sqlLocalHome"
      /bin/chmod -R 770 "$sqlLocalHome"
      /bin/chmod +a "$userID allow list,add_file,search,delete,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit" "$sqlLocalHome"
      /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET permissionsCheckDate='$sqlDate' WHERE userID='$userID';"
         
done < "$scriptPath"stafffolderList.txt
rm -rf "$scriptPath"stafffolderList.txt




####################################################################################################################
# SECTION SIX --> FIX MUNIS FUCKUP TRANSFERS
#
# THis section moves folders that were transferred due to clerical errors in MUNIS back into the students sharepoint
####################################################################################################################
echo "-------------------------STAFF FOLDER RESURRECTION------------------------" >> "$logFile"
/usr/bin/sqlite3 "$sqlDatabase" "SELECT userID FROM staff WHERE transferCountdown is '0' AND lastChecked is '$sqlDate';" >> "$scriptPath"fixTransferStaffErrorsList.txt
while read line; do
      userID="$line"
      sqlLocalHome=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT localHome FROM staff WHERE userid='$userID';"`
      sqlTransferHome=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT transferHome From staff WHERE userid='$userID';"`
      userRealName=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT userName FROM staff WHERE userid='$userID';"`     
                  
      /bin/echo "`date "+%H:%M:%S"` - RISE FROM YOUR GRAVE: $userID AKA $userRealName" >> "$logFile"
      /bin/cp -R "$sqlTransferHome" "$sqlLocalHome"
      /bin/rm -rf "$sqlTransferHome"
      /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET transferDate='RISEFROMYOURGRAVE $sqlDate' WHERE userID='$userID';"
      /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET transferCountdown=null WHERE userID='$userID';"

done < "$scriptPath"fixTransferStaffErrorsList.txt
rm -rf "$scriptPath"fixTransferStaffErrorsList.txt





####################################
# SECTION SEVEN --> CHECK PERMISSIONS
#
# Setups permissions for Staff Share
####################################

##################
# Top Level Folder
##################
/usr/sbin/chown admin:admin "/Volumes/Data/Staff/"
/bin/chmod 770 "/Volumes/Data/Staff/"
/bin/chmod -R +a "xnet-staff allow list,add_file,search,delete,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit" "/Volumes/Data/Staff/"
/bin/chmod +a "$staffGroup allow list,search,limit_inherit" "/Volumes/Data/Staff"

########################
# Staff Personal Folders
########################
/usr/bin/sqlite3 "$sqlDatabase" "SELECT userID FROM staff WHERE lastChecked is '$sqlDate';" >> "$scriptPath"staffPermissionsList.txt
while read line; do
      userID="$line"
      sqlLocalHome=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT localHome FROM staff WHERE userid='$userID';"`
      sqlPermissionsDate=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT permissionsCheckDate FROM staff WHERE userid='$userID'"`

      if [ "$sqlPermissionsDate" != "$sqlDate" ] && [ "$sqlPermissionsDate" != "CHARLATAN" ]; then
         /usr/sbin/chown -R "$userID":admin "$sqlLocalHome"
         /bin/chmod -R 770 "$sqlLocalHome"
         /bin/chmod +a "$userID allow list,add_file,search,delete,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit" "$sqlLocalHome"    
         /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET permissionsCheckDate='$sqlDate' WHERE userID='$userID';"
      fi       
done < "$scriptPath"staffPermissionsList.txt
rm -rf "$scriptPath"staffPermissionsList.txt





######################################################################
# SECTION EIGHT --> TRANSFER DATA AND WARNING EMAILS
#
# Moves staff folders that have been removed from building staff group
# This action happens seven days after removal
######################################################################
echo "-------------------------STAFF TRANSFER DATA------------------------------" >> "$logFile"
/usr/bin/sqlite3 "$sqlDatabase" "SELECT userID FROM staff WHERE lastChecked NOT LIKE '$sqlDate';" >> "$scriptPath"staffTransferList.txt
while read line; do
      userID="$line"
      sqlTransferCountdown=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT transferCountdown FROM staff WHERE userid='$userID';"`
      sqlLocalHome=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT localHome FROM staff WHERE userid='$userID';"`
      sqlTransferHome=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT transferHome From staff WHERE userid='$userID';"`
      sqlEmailAddress=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT emailAddress FROM staff WHERE userid='userID';"`
      
      
            if [ "$sqlTransferCountdown" = "1" ];
               then
                   /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET transferCountdown='0' WHERE userID='$userID';"
                   /bin/cp -R "$sqlLocalHome" "$sqlTransferHome"
                   sqlLocalSize=`du -s "$sqlLocalHome" | cut -f1`
                   sqlTransferSize=`du -s "$sqlTransferHome" | cut -f1`
                   
                   if [ "$sqlLocalSize" = "$sqlTransferSize" ]; then
                          /bin/rm -rf "$sqlLocalHome"
                          echo "`date "+%H:%M:%S"` - TRANSFERRING FOLDER: Sucessfully transferred $userID's folder" >> "$logFile"
                          /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET transferDate='$sqlDate' WHERE userID='$userID';"
                      else
                          echo "`date "+%H:%M:%S"` - TRANSFERRING FOLDER: Failed transferred $userID's folder" >> "$logFile"
                   fi
                   
                   /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET emailWorkOrderSystem='$sqlDate' WHERE userID='$userID';"                                    
                   echo "`date "+%H:%M:%S"` - CREATING WORK ORDER: $userID" >> "$logFile" 
                   #mail   
            fi            
            
            if [ "$sqlTransferCountdown" = "2" ];
               then
                   /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET transferCountdown='1' WHERE userID='$userID';"
                   /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET emailWarningSecond='$sqlDate' WHERE userID='$userID';"
                   echo "`date "+%H:%M:%S"` - WARNING: Transferring $userID's folder in 1 days" >> "$logFile"     
                   echo "`date "+%H:%M:%S"` - WARNING: Emailed warning to $userID" >> "$logFile"                                 
                   #/usr/bin/mail -s "Folder Creator warning - Hey Bonita " $sqlEmailAddress
            fi
            
            if [ "$sqlTransferCountdown" = "3" ];
               then
                   /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET transferCountdown='2' WHERE userID='$userID';" 
                   /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET emailWarningFirst='$sqlDate' WHERE userID='$userID';"
                   
                   echo "`date "+%H:%M:%S"` - WARNING: Transferring $userID's folder in 2 days" >> "$logFile"     
                   echo "`date "+%H:%M:%S"` - WARNING: Emailed warning to $userID" >> "$logFile"                  
                   #/usr/bin/mail -s "Folder Creator warning - Hey Bonita " "$sqlEmailAddress"
            fi
            
            if [ "$sqlTransferCountdown" = "4" ];
               then
                   /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET transferCountdown='3' WHERE userID='$userID';"
                   echo "`date "+%H:%M:%S"` - WARNING: Transferring $userID's folder in 3 days" >> "$logFile"                   
            fi
            
            if [ "$sqlTransferCountdown" = "5" ];
               then
                   /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET transferCountdown='4' WHERE userID='$userID';"
                   echo "`date "+%H:%M:%S"` - WARNING: Transferring $userID's folder in 4 days" >> "$logFile"        
            fi

            if [ "$sqlTransferCountdown" = "6" ];
               then
                   /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET transferCountdown='5' WHERE userID='$userID';" 
                   echo "`date "+%H:%M:%S"` - WARNING: Transferring $userID's folder in 5 days" >> "$logFile" 
            fi

            if [ "$sqlTransferCountdown" = "7" ];
               then
                   /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET transferCountdown='6' WHERE userID='$userID';"
                   echo "`date "+%H:%M:%S"` - WARNING: Transferring $userID's folder in 6 days" >> "$logFile"        
            fi

            if [ -z "$sqlTransferCountdown" -a "$sqlTransferCountdown"!=" " ];
               then
                   /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET transferCountdown='7' WHERE userID='$userID';"
                   echo "`date "+%H:%M:%S"` - WARNING: Transferring $userID's folder in 7 days" >> "$logFile"     
            fi
                           
done < "$scriptPath"staffTransferList.txt
rm -rf "$scriptPath"staffTransferList.txt





#############################################################################################################################################################################################
#############################################################################################################################################################################################
#############################################################################################################################################################################################
#
#                                                                                              STUDENT SECTION
#
#############################################################################################################################################################################################
#############################################################################################################################################################################################
#############################################################################################################################################################################################





#########################################################################
# SECTION NINE --> STUDENT AUDIT
#
# Audits building student group and adds all new users to sqlite database
#########################################################################
echo "-------------------------STUDENT AUDIT------------------------------------" >> "$logFile"
dscl /Active\ Directory/FSD/All\ Domains/ -read /Groups/"$studentGroup" GroupMembership | awk 'gsub(/FSD/, "\n")' | grep s[0-9] | sed 's/[!@#\$%^&*()]//g' >> "$scriptPath"studentList.txt

##########################################
# Checks to see if the user already exists
##########################################
while read line; do
      userID="$line"
      quickCheck=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT userID FROM students WHERE userID='$userID';"`

      if [ "$quickCheck" != "$userID" ]; then
          echo "$userID" >> "$scriptPath"studentListFiltered.txt
      else
          echo "$userID" >> "$scriptPath"studentNameCheck.txt
          /usr/bin/sqlite3 "$sqlDatabase" "UPDATE students SET lastChecked='$sqlDate' WHERE userID='$userID';"
      fi      
      
done < "$scriptPath"studentList.txt
rm -rf "$scriptPath"studentList.txt

###########################
# Adds new student accounts
###########################
while read line; do
      userID="$line"
      serverName=`dscl /Active\ Directory/FSD/All\ Domains/ -read /Users/"$userID" SMBHome | grep -o [a-z][a-z][a-z]-xserve`
      userRealName=`dscl /Active\ Directory/FSD/All\ Domains/ -read /Users/"$userID" RealName | grep "," | cut -c 2-`
      graduationYear=`dscl /Active\ Directory/FSD/All\ Domains/ -read /Users/"$userID" SMBHome | grep -o "Class of [0-9][0-9][0-9][0-9]" | cut -c 10-`
      smbHomeRaw=`dscl /Active\ Directory/FSD/All\ Domains/ -read /Users/"$userID" SMBHome | grep "$building-" | cut -c 2-`
      smbHomeProcessed=$(echo "$smbHomeRaw" | sed 's:\\:/:g')
      localHome=$(echo "$smbHomeProcessed" | sed 's://'$serverName':/Volumes/Data:g')
      transferHome=$(echo "$smbHomeProcessed" | sed 's://'$serverName':/Volumes/Data/Transferred:g')
                  
      apostropheNameCheck=$(echo "$userRealName" | grep "'")
      apostropheSMBCheck=$(echo "$smbHomeRaw" | grep "'")

      ####################################################
      # Checks to see if there is a apostrophe in the name
      ####################################################
      if [ "$userRealName" = "$apostropheNameCheck" ];
         then
             userRealName=$(echo "$userRealName" | sed "s/'/\''/g")            
             /usr/bin/sqlite3 "$sqlDatabase" "INSERT into students (userID, userName, graduationYear, adGroup, lastChecked) values ('$userID', '$userRealName', '$graduationYear','$studentGroup', '$sqlDate');"
             echo "$userRealName contains apostrophe"
             echo "`date "+%H:%M:%S"` - ADDING TO SQLITE DATABASE: $userID AKA $userRealName" >> "$logFile"         
         else
             /usr/bin/sqlite3 "$sqlDatabase" "INSERT into students (userID, userName, graduationYear, adGroup, adHome, localHome, transferHome, lastChecked) values ('$userID', '$userRealName', '$graduationYear','$studentGroup', '$smbHomeRaw', '$localHome', '$transferHome', '$sqlDate');"
             echo "`date "+%H:%M:%S"` - ADDING TO SQLITE DATABASE: $userID AKA $userRealName" >> "$logFile"     
      fi

      ########################################################
      # Checks to see if there is a apostrophe in the smb path
      ########################################################      
      if [ "$smbHomeRaw" = "$apostropheSMBCheck" ];
         then
             smbHomeProcessed=$(echo "$smbHomeProcessed" | sed "s/'/\''/g")
             localHome=$(echo "$localHome" | sed "s/'/\''/g")
             transferHome=$(echo "$transferHome" | sed "s/'/\''/g")
      
             /usr/bin/sqlite3 "$sqlDatabase" "UPDATE students SET adHome='$smbHomeProcessed', localHome='$localHome', transferHome='$transferHome' WHERE userID='$userID';"    
         else
             /usr/bin/sqlite3 "$sqlDatabase" "UPDATE students SET adHome='$smbHomeProcessed', localHome='$localHome', transferHome='$transferHome' WHERE userID='$userID';"            
      fi        

      ######################
      # Does Not Belong Here
      ######################
      if [ -z "$transferHome" -a "$transferHome"!=" " ];
      then
         /usr/bin/sqlite3 "$sqlDatabase" "UPDATE students SET adHome='CHARLATAN', localHome='CHARLATAN', localHomeCreationDate='CHARLATAN', permissionsCheckDate='CHARLATAN', transferHome='CHARLATAN', transferDate='CHARLATAN',transferCountdown='CHARLATAN' WHERE userID='$userID';"
         echo "`date "+%H:%M:%S"` - SPECIAL USER: $userID AKA $userRealName does not belong on this server" >> "$logFile" 
      fi   
             
done < "$scriptPath"studentListFiltered.txt
rm -rf "$scriptPath"studentListFiltered.txt





###############################################################################################################
# SECTION TEN --> NAME UPDATE
#
# This section updates the name  and smb path of users that have been previously entered in the sqlite database
###############################################################################################################
echo "-------------------------UPDATING STUDENT INFORMATION---------------------" >> "$logFile"
while read line; do
      userID="$line"
      sqlLocalHome=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT adHome FROM students WHERE userid='$userID';"`      

      if [ "$sqlLocalHome" != "CHARLATAN" ];
         then
             echo "$userID" >> "$scriptPath"studentNameCheckFiltered.txt         
      fi

done < "$scriptPath"studentNameCheck.txt
rm -rf "$scriptPath"studentNameCheck.txt



while read line; do
      userID="$line"
      serverName=`dscl /Active\ Directory/FSD/All\ Domains/ -read /Users/"$userID" SMBHome | grep -o [a-z][a-z][a-z]-xserve`
      userRealName=`dscl /Active\ Directory/FSD/All\ Domains/ -read /Users/"$userID" RealName | grep "," | cut -c 2-`
      smbHomeRaw=`dscl /Active\ Directory/FSD/All\ Domains/ -read /Users/"$userID" SMBHome | grep "$building-" | cut -c 2-`
      smbHomeProcessed=$(echo "$smbHomeRaw" | sed 's:\\:/:g')
      localHome=$(echo "$smbHomeProcessed" | sed 's://'$serverName':/Volumes/Data:g')
      transferHome=$(echo "$smbHomeProcessed" | sed 's://'$serverName':/Volumes/Data/Transferred:g')     
      emailAddress=`dscl /Active\ Directory/FSD/All\ Domains/ -read /Users/"$userID" EMailAddress | cut -c 15-`

      sqlLocalHome=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT adHome FROM students WHERE userid='$userID';"`      

      if [ "$smbHomeProcessed" != "$sqlLocalHome" ];
         then
             sqlOldHome=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT localHome FROM students WHERE userid='$userID';"`
             
             apostropheNameCheck=$(echo "$userRealName" | grep "'")
             apostropheSMBCheck=$(echo "$smbHomeRaw" | grep "'")
             apostropheEmailCheck=$(echo "$emailAddress" | grep "'")    
 
             ####################################################
             # Checks to see if there is a apostrophe in the name
             ####################################################
             if [ "$userRealName" = "$apostropheNameCheck" ];
                then
                    userRealName=$(echo "$userRealName" | sed "s/'/\''/g")  
                    echo "apostrophe name is $userRealName"          
                    /usr/bin/sqlite3 "$sqlDatabase" "UPDATE students SET userName='$userRealName' WHERE userID='$userID';"
                    echo "$userRealName contains apostrophe"
                else            
                    /usr/bin/sqlite3 "$sqlDatabase" "UPDATE students SET userName='$userRealName' WHERE userID='$userID';"
             fi

             ########################################################
             # Checks to see if there is a apostrophe in the smb path
             ########################################################      
             if [ "$smbHomeRaw" = "$apostropheSMBCheck" ];
                then
                    smbHomeProcessed=$(echo "$smbHomeProcessed" | sed "s/'/\''/g")
                    localHome=$(echo "$localHome" | sed "s/'/\''/g")
                    transferHome=$(echo "$transferHome" | sed "s/'/\''/g")
      
                    /usr/bin/sqlite3 "$sqlDatabase" "UPDATE students SET adHome='$smbHomeProcessed', localHome='$localHome', transferHome='$transferHome' WHERE userID='$userID';"   
                else
                    /usr/bin/sqlite3 "$sqlDatabase" "UPDATE students SET adHome='$smbHomeProcessed', localHome='$localHome', transferHome='$transferHome' WHERE userID='$userID';"            
             fi        
                                
             echo "`date "+%H:%M:%S"` - RECORD UPDATED: $userID aka $userRealName" >> "$logFile"
                                    
             /bin/mv "$sqlOldHome" "$localHome"
             echo "$sqlOldHome $localHome"              
      fi
                 
done < "$scriptPath"studentNameCheckFiltered.txt
rm -rf "$scriptPath"studentNameCheckFiltered.txt





#######################################################################################
# SECTION ELEVEN --> FOLDER CREATION
#
# This section creates folders for all Students that do not have a folder creation date
#######################################################################################
echo "-------------------------STUDENT FOLDER CREATION--------------------------" >> "$logFile"
/usr/bin/sqlite3 "$sqlDatabase" "SELECT userID FROM students WHERE localHomeCreationDate IS NULL;" >> "$scriptPath"studentfolderList.txt
while read line; do
      userID="$line"
      sqlLocalHome=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT localHome FROM students WHERE userid='$userID';"`
           
      /bin/echo "`date "+%H:%M:%S"` - CREATING FOLDER: $userID" >> "$logFile" 
      /usr/bin/sqlite3 "$sqlDatabase" "UPDATE students SET localHomeCreationDate='$sqlDate' WHERE userID='$userID';"
      /bin/mkdir -p "$sqlLocalHome"
      /usr/sbin/chown -R "$userID":admin "$sqlLocalHome"
      /bin/chmod -R 770 "$sqlLocalHome"
      /bin/chmod +a "$userID allow list,add_file,search,delete,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit" "$sqlLocalHome"
      /usr/bin/sqlite3 "$sqlDatabase" "UPDATE staff SET permissionsCheckDate='$sqlDate' WHERE userID='$userID';"
         
done < "$scriptPath"studentfolderList.txt
rm -rf "$scriptPath"studentfolderList.txt





##########################################################################################################################
# SECTION TWELVE --> FIX POWERSCHOOL FUCKUP TRANSFERS
#
# THis section moves folders that were transferred due to clerical errors in PowerSchool back into the students sharepoint
##########################################################################################################################
echo "-------------------------STUDENT FOLDER RESURRECTION----------------------" >> "$logFile"
/usr/bin/sqlite3 "$sqlDatabase" "SELECT userID FROM students WHERE transferCountdown is '0' AND lastChecked is '$sqlDate';" >> "$scriptPath"fixTransferStudentsErrorsList.txt
while read line; do
      userID="$line"
      sqlLocalHome=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT localHome FROM students WHERE userid='$userID';"`
      sqlTransferHome=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT transferHome From students WHERE userid='$userID';"`     
      userRealName=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT userName FROM students WHERE userid='$userID';"`     
                  
      /bin/echo "`date "+%H:%M:%S"` - RISE FROM YOUR GRAVE: $userID AKA $userRealName" >> "$logFile"
      /bin/cp -R "$sqlTransferHome" "$sqlLocalHome"
      /bin/rm -rf "$sqlTransferHome"
      /usr/bin/sqlite3 "$sqlDatabase" "UPDATE students SET transferDate='RISEFROMYOURGRAVE $sqlDate' WHERE userID='$userID';"
      /usr/bin/sqlite3 "$sqlDatabase" "UPDATE students SET transferCountdown=null WHERE userID='$userID';"

done < "$scriptPath"fixTransferStudentsErrorsList.txt
rm -rf "$scriptPath"fixTransferStudentsErrorsList.txt





#####################################
# SECTION THIRTEEN --> CHECK PERMISSIONS
#
# Setup permissions for Student Share
#####################################

##################
# Top Level Folder
##################
/usr/sbin/chown admin:admin "/Volumes/Data/Students/"
/bin/chmod 770 "/Volumes/Data/Students/"
/bin/chmod +a "xnet-staff allow list,search,limit_inherit" "/Volumes/Data/Students/"
/bin/chmod +a "$staffGroup allow list,search,limit_inherit" "/Volumes/Data/Students/"
/bin/chmod +a "$studentGroup allow list,search,limit_inherit" "/Volumes/Data/Students/"

#####################
# Class Level Folders
#####################
ls -la /Volumes/Data/Students/ | grep -o "Class of [0-9][0-9][0-9][0-9]" >> "$scriptPath"classFolders.txt

while read line; do 
      class="$line"
      /usr/sbin/chown admin:admin "/Volumes/Data/Students/$class"
      /bin/chmod 770 "/Volumes/Data/Students/$class"
      /bin/chmod -R +a "xnet-staff allow list,add_file,search,delete,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit" "/Volumes/Data/Students/$class"    
      /bin/chmod -R +a "$staffGroup allow list,add_file,search,delete,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit" "/Volumes/Data/Students/$class"    
      /bin/chmod +a "$studentGroup allow list,search,limit_inherit" "/Volumes/Data/Students/$class"    
      if [ ! -d "/Volumes/Data/Transferred/Students/$class" ];
         then
             /bin/mkdir -p "/Volumes/Data/Transferred/Students/$class"
      fi
      
done < "$scriptPath"classFolders.txt
rm -rf "$scriptPath"classFolders.txt

#######################
# Student Level Folders
#######################
/usr/bin/sqlite3 "$sqlDatabase" "SELECT userID FROM students WHERE lastChecked is '$sqlDate';" >> "$scriptPath"studentPermissionsList.txt
while read line; do
      userID="$line"
      sqlLocalHome=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT localHome FROM students WHERE userid='$userID';"`
      sqlPermissionsDate=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT permissionsCheckDate FROM students WHERE userid='$userID'"`

      if [ "$sqlPermissionsDate" != "$sqlDate" ] && [ "$sqlPermissionsDate" != "CHARLATAN" ]; then
         /usr/sbin/chown -R "$userID":admin "$sqlLocalHome"
         /bin/chmod -R 770 "$sqlLocalHome"
         /bin/chmod +a "$userID allow list,add_file,search,delete,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit" "$sqlLocalHome"    
         /usr/bin/sqlite3 "$sqlDatabase" "UPDATE students SET permissionsCheckDate='$sqlDate' WHERE userID='$userID';"
      fi       
done < "$scriptPath"studentPermissionsList.txt
rm -rf "$scriptPath"studentPermissionsList.txt





##########################################################################
# SECTION FOURTEEN --> TRANSFER STUDENT DATA 
#
# Moves student folders that have been removed from building student group
# This action happens four days after removal
##########################################################################
echo "-------------------------STUDENT TRANSFER DATA----------------------------" >> "$logFile"
/usr/bin/sqlite3 "$sqlDatabase" "SELECT userID FROM students WHERE lastChecked NOT LIKE '$sqlDate';" >> "$scriptPath"studentTransferList.txt
while read line; do
      userID="$line"
      sqlTransferCountdown=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT transferCountdown FROM students WHERE userid='$userID';"`
      sqlLocalHome=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT localHome FROM students WHERE userid='$userID';"`
      sqlTransferHome=`/usr/bin/sqlite3 "$sqlDatabase" "SELECT transferHome From students WHERE userid='$userID';"`     
      
            if [ "$sqlTransferCountdown" = "1" ];
               then
                   /usr/bin/sqlite3 "$sqlDatabase" "UPDATE students SET transferCountdown='0' WHERE userID='$userID';"
                   /bin/cp -R "$sqlLocalHome" "$sqlTransferHome"
                   sqlLocalSize=`du -s "$sqlLocalHome" | cut -f1`
                   sqlTransferSize=`du -s "$sqlTransferHome" | cut -f1`
                   
                   if [ "$sqlLocalSize" = "$sqlTransferSize" ]; then
                          /bin/rm -rf "$sqlLocalHome"
                          echo "`date "+%H:%M:%S"` - TRANSFERRING FOLDER: Sucessfully transferred $userID's folder" >> "$logFile"
                          /usr/bin/sqlite3 "$sqlDatabase" "UPDATE students SET transferDate='$sqlDate' WHERE userID='$userID';"
                      else
                          echo "`date "+%H:%M:%S"` - TRANSFERRING FOLDER: Failed transferred $userID's folder" >> "$logFile"
                   fi                   
            fi            
            
            if [ "$sqlTransferCountdown" = "2" ];
               then
                   /usr/bin/sqlite3 "$sqlDatabase" "UPDATE students SET transferCountdown='1' WHERE userID='$userID';"
                   echo "`date "+%H:%M:%S"` - WARNING: Transferring $userID's folder in 1 days" >> "$logFile"     
            fi
            
            if [ "$sqlTransferCountdown" = "3" ];
               then
                   /usr/bin/sqlite3 "$sqlDatabase" "UPDATE students SET transferCountdown='2' WHERE userID='$userID';"                  
                   echo "`date "+%H:%M:%S"` - WARNING: Transferring $userID's folder in 2 days" >> "$logFile"     
            fi
            
            if [ "$sqlTransferCountdown" = "4" ];
               then
                   /usr/bin/sqlite3 "$sqlDatabase" "UPDATE students SET transferCountdown='3' WHERE userID='$userID';"
                   echo "`date "+%H:%M:%S"` - WARNING: Transferring $userID's folder in 3 days" >> "$logFile"                   
            fi
            
            if [ -z "$sqlTransferCountdown" -a "$sqlTransferCountdown"!=" " ];
               then
                   /usr/bin/sqlite3 "$sqlDatabase" "UPDATE students SET transferCountdown='4' WHERE userID='$userID';"
                   echo "`date "+%H:%M:%S"` - WARNING: Transferring $userID's folder in 4 days" >> "$logFile"     
            fi               
                           
done < "$scriptPath"/studentTransferList.txt
rm -rf "$scriptPath"/studentTransferList.txt





################################################
# SECTION FIFTEEN --> TRANSFER FOLDER PERMISSIONS
#
# Setup permissions for Transferred Share
################################################
/bin/chmod -R +a "xnet-staff allow list,search,readattr,readextattr,readsecurity,file_inherit,directory_inherit" /Volumes/Data/Transferred/ 

/bin/chmod -R 770 /Volumes/Data/Transferred/
/usr/sbin/chown admin:admin /Volumes/Data/Transferred/

/bin/chmod -R 770 /Volumes/Data/Transferred/Staff
/usr/sbin/chown admin:admin /Volumes/Data/Transferred/Staff/

/bin/chmod -R 770 /Volumes/Data/Transferred/Students
/usr/sbin/chown admin:admin /Volumes/Data/Transferred/Students/
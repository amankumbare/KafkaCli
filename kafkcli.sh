#!/bin/bash
#***************************************************************************
#This script will only work from kafka broker on CDP.
#If you want to run this on another cluster  please make sure below variables are updated :
#SERVER
#SECURITY_PROTOCOL
#KAFKA_KEYTAB
#***************************************************************************

export KAFKA_PROCESS_DIR=$(ls -1drt /var/run/cloudera-scm-agent/process/*KAFKA_BROKER | tail -1)
export SERVER=$(grep -i listeners $KAFKA_PROCESS_DIR/kafka.properties | awk -F "/" '{print $3}' | sed 's/,//' )
export SECURITY_PROTOCOL=$(grep -i listeners $KAFKA_PROCESS_DIR/kafka.properties | awk -F "=" '{print $2}' | awk -F ":" '{print $1}')
export KAFKA_KEYTAB=$KAFKA_PROCESS_DIR/kafka.keytab

exit_on_failure () {
if [ $? -eq 0 ]
then
    echo ""
else
	 echo "Please check the keytab and principal"
	 exit 1;
fi
}

# checking the security protocol to confirm if kerberos is enabled:
if [ "$SECURITY_PROTOCOL" == "SASL_PLAINTEXT" ]  || [ "$SECURITY_PROTOCOL" == "PLAINTEXTSASL" ] || [ "$SECURITY_PROTOCOL" == "SASL_SSL" ] ; then
	while true; do
      	read -p $'\n\e[96mPlease confirm if you want to run as Kafka kerberos user (y/n) ? :\e[0m' yn
      	case $yn in
         [Yy]* )  KAFKAUSER=yes ; break;;
         [Nn]* )  KAFKAUSER=no ; break;;
         * ) echo "Please answer yes or no.";;
      	esac
	done
	
	if  [ "$KAFKAUSER" == "no" ];then
 		read -p "Enter Complete path to Keytab: " Keytab
 		export PRINCIPAL=$(klist -kt $Keytab | awk '{print $4}' | tail -1 )
 		echo "Running : kinit -kt $Keytab $PRINCIPAL "
 		kinit -kt $Keytab $PRINCIPAL
 		exit_on_failure
	else
		export PRINCIPAL=$(klist -kt $KAFKA_PROCESS_DIR/kafka.keytab | awk '{print $4}' | tail -1 )
		echo "Running  : kinit -kt $KAFKA_PROCESS_DIR/kafka.keytab $PRINCIPAL "
		kinit -kt $KAFKA_KEYTAB $PRINCIPAL
		exit_on_failure
	fi
else
 :
fi

# This properties file will be used by all the commands :
PROPERTIES_FILE=/tmp/client.properties

if [ "$SECURITY_PROTOCOL" == "SASL_SSL" ]  || [ "$SECURITY_PROTOCOL" == "SSL" ] ; then
	read -p "Truststore Location: " TRUSTLOC
	read -p "Truststore Password: " TRUSTPWD
	read -p "Keystore Location (if client authentication is enable else press enter):" KEYLOC
	read -p "Keystore Password (if client authentication is enable else press enter):" KEYPWD
	read -p "Key Password (if client authentication is enable else press enter):" KPWD
	echo "ssl.truststore.location=$TRUSTLOC" >> $PROPERTIES_FILE
	echo "ssl.truststore.password=$TRUSTPWD" >> $PROPERTIES_FILE
	echo "ssl.keystore.location=$KEYLOC" >> $PROPERTIES_FILE
	echo "ssl.keystore.password=$KEYPWD" >> $PROPERTIES_FILE
	echo "ssl.key.password=$KPWD"  >> $PROPERTIES_FILE
	echo "security.protocol=$SECURITY_PROTOCOL" >> $PROPERTIES_FILE
else
echo "security.protocol=$SECURITY_PROTOCOL" >> $PROPERTIES_FILE
fi


# JAAS file template, you can update this is you want to use "useKeytab"
if [ ! -f /tmp/client_jaas.conf ]
then
   cat <<EOF > /tmp/client_jaas.conf
KafkaClient {
com.sun.security.auth.module.Krb5LoginModule required
useTicketCache=true
renewTicket=true
serviceName="kafka";
};
Client {
com.sun.security.auth.module.Krb5LoginModule required
useTicketCache=true
renewTicket=true
serviceName="zookeeper";
};
EOF
fi

echo "exporting JAAS file /tmp/client_jaas.conf"
export KAFKA_OPTS="-Djava.security.auth.login.config=/tmp/client_jaas.conf"


PS3='Please enter your choice: '
# Checking if the commands are available on the node:
check_kafka_topic_command () {
if ! [ -x "$(command -v kafka-topics)" ]; then
  		   	echo -e "\e[31mError: kafka-topics script is not available.\e[0m"
  		   	echo -e "\e[31mPlease install kafka client\e[0m"
  		   	exit 1
		   fi
}

check_kafka_producer_command () {
if ! [ -x "$(command -v kafka-console-producer)" ]; then
  		   	echo -e "\e[31mError: kafka-console-producer script is not available.\e[0m"
  		   	echo -e "\e[31mPlease install kafka client\e[0m"
  		   	exit 1
		   fi
}

check_kafka_consumer_command () {
if ! [ -x "$(command -v kafka-console-consumer)" ]; then
  		   	echo -e "\e[31mError: kafka-console-producer script is not available.\e[0m"
  		   	echo -e "\e[31mPlease install kafka client\e[0m"
  		   	exit 1
		   fi
}

check_kafka_consumer_group_command () {
if ! [ -x "$(command -v kafka-consumer-groups)" ]; then
  		   	echo -e "\e[31mError: kafka-consumer-groups script is not available.\e[0m"
  		   	echo -e "\e[31mPlease install kafka client\e[0m"
  		   	exit 1
		   fi
}

options=(
	"LIST ALL TOPIC" 
	"DESCRIBE ALL THE TOPICS" 
	"TOPICS WHOSE PARTITIONS ARE NOT AVAILABLE" 
	"TOPICS WHICH DOES NOT MEET min.insync.replicas" 
	"TOPICS WHICH DOES NOT MEET THE REPLICATION FACTOR OR REPLICAS ARE MISSING" 
	"DESCRIBE A SPECIFIC TOPIC" 
	"CREATE A TOPIC"
	"PRODUCE MESSAGES TO TOPIC"
	"CONSUME MESSAGE FROM TOPIC"
	"DESCRIBE CONSUMER GROUP"
	"Quit"
)

select opt in "${options[@]}"
do
    case $opt in
        "LIST ALL TOPIC")
           check_kafka_topic_command
		   echo "Running Command : kafka-topics --bootstrap-server $SERVER --list --command-config $PROPERTIES_FILE"
		   kafka-topics --bootstrap-server $SERVER --list --command-config $PROPERTIES_FILE
            ;;
        "DESCRIBE ALL THE TOPICS")
            check_kafka_topic_command
            echo "Running Command : kafka-topics --bootstrap-server $SERVER --describe --command-config $PROPERTIES_FILE"
			kafka-topics --bootstrap-server $SERVER --describe --command-config $PROPERTIES_FILE
            ;;
        "TOPICS WHOSE PARTITIONS ARE NOT AVAILABLE")
         	check_kafka_topic_command
            echo "Running Command : kafka-topics --bootstrap-server $SERVER --describe --command-config $PROPERTIES_FILE --unavailable-partitions "
			kafka-topics --bootstrap-server $SERVER --describe --command-config $PROPERTIES_FILE --unavailable-partitions
            ;;
        "TOPICS WHICH DOES NOT MEET min.insync.replicas")
        	check_kafka_topic_command
        	echo "Running Command : kafka-topics --bootstrap-server $SERVER --describe --command-config $PROPERTIES_FILE --under-min-isr-partitions "
			kafka-topics --bootstrap-server $SERVER --describe --command-config $PROPERTIES_FILE --under-min-isr-partitions
			;;
		"TOPICS WHICH DOES NOT MEET THE REPLICATION FACTOR OR REPLICAS ARE MISSING")
			check_kafka_topic_command
			echo "Running Command : kafka-topics --bootstrap-server $SERVER --describe --command-config $PROPERTIES_FILE --under-replicated-partitions"
			kafka-topics --bootstrap-server $SERVER --describe --command-config $PROPERTIES_FILE --under-replicated-partitions
			;;
		"DESCRIBE A SPECIFIC TOPIC")
			check_kafka_topic_command
			read -p "Enter Topic Name: " TOPIC
            echo "Running Command : kafka-topics --bootstrap-server $SERVER --topic $TOPIC --describe --command-config $PROPERTIES_FILE"
			kafka-topics --bootstrap-server $SERVER --topic $TOPIC --describe --command-config $PROPERTIES_FILE
			;;
		"CREATE A TOPIC")
			check_kafka_topic_command
			read -p "Enter Topic Name: " TOPIC
			read -p "Enter Number Of Partitions: " PNO
			read -p "Enter The Number Of Replicas: " RF
			read -p "Enter Additional Arguments to pass in the format --Argument value: " ADDTPCON
			echo "Running Command : kafka-topics --bootstrap-server $SERVER --topic $TOPIC --create --partitions $PNO --replication-factor $RF --command-config $PROPERTIES_FILE $ADDTPCON"
			kafka-topics --bootstrap-server $SERVER --topic $TOPIC --create --partitions $PNO --replication-factor $RF --command-config $PROPERTIES_FILE $ADDTPCON
			;;
		"PRODUCE MESSAGES TO TOPIC")
			check_kafka_producer_command
			read -p "Enter Topic Name: " TOPIC
			read -p "How Many Messages to produce " MSGNU
			read -p "Enter Additional Arguments to pass in the format --Argument value : " ADDTPCON
			if [ ! -f  $( eval echo /tmp/$MSGNU.txt ) ]
			then
			for a in $( eval echo {1..$MSGNU} ); do echo "This is Message no $a"; done > /tmp/$MSGNU.txt
			else
			echo > /tmp/$MSGNU.txt
			for a in $( eval echo {1..$MSGNU} ); do echo "This is Message no $a"; done > /tmp/$MSGNU.txt
			fi
			echo "Running Command : kafka-console-producer --bootstrap-server $SERVER --producer.config $PROPERTIES_FILE --topic $TOPIC $ADDTPCON < /tmp/$MSGNU.txt"
			kafka-console-producer --bootstrap-server $SERVER --producer.config $PROPERTIES_FILE --topic $TOPIC $ADDTPCON < /tmp/$MSGNU.txt
			echo "Delete the file /tmp/$MSGNU.txt"
			;;
		"CONSUME MESSAGE FROM TOPIC")
			check_kafka_consumer_command
			read -p "Enter Topic Name: " TOPIC
			read -p "Enter Additional Arguments to pass in the format --Argument value : " ADDTPCON
			echo "Running Command : kafka-console-consumer --bootstrap-server $SERVER --consumer.config $PROPERTIES_FILE --topic $TOPIC $ADDTPCON"
			kafka-console-consumer --bootstrap-server $SERVER --consumer.config $PROPERTIES_FILE --topic $TOPIC $ADDTPCON
			;;
		"DESCRIBE CONSUMER GROUP")
			check_kafka_consumer_group_command
			read -p "Enter Consumer Group: " CGRP
			read -p "Enter Additional Arguments to pass in the format --Argument value : " ADDTPCON
			echo "Running Command : kafka-consumer-groups --bootstrap-server $SERVER --describe  --group $CGRP --command-config /tmp/client.properties"
			kafka-consumer-groups --bootstrap-server $SERVER --describe --command-config $PROPERTIES_FILE --group $CGRP  $ADDTPCON
			;;
        "Quit")
            break
            ;;
        *) echo "invalid option $REPLY";;
    esac
done


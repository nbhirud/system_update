FROM ubuntu
RUN apt-get update -y
# for ping command
RUN apt-get install -y iputils-ping 
# for ip command
RUN apt install -y iproute2
FROM ubuntu:18.04

RUN apt-get update && \
    apt-get upgrade -y
RUN apt-get install -y make git gcc

ENV SRC=/src
RUN mkdir -p $SRC

ENV SMAKE=/smake

RUN git clone https://github.com/prosyslab/smake.git
WORKDIR $SRC

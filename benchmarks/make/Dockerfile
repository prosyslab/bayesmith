FROM prosyslab/continuous-reasoning-base

ARG SHA

RUN apt-get install -y wget m4 pkg-config gettext autopoint texinfo

COPY build.sh $SRC
ENV SHA=$SHA
ENV PROGRAM=make

RUN mkdir $PROGRAM
WORKDIR $PROGRAM
RUN git init && git remote add origin https://github.com/mirror/make.git && \
    git fetch --depth 1 origin $SHA && git checkout $SHA
RUN $SRC/build.sh

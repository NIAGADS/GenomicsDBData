# syntax=docker/dockerfile:1
ARG USER=genomicsdb
ARG POSTGRES_VERSION=14
ARG GENOME_BUILD=GRCh38
ARG SAMTOOLS_VERSION=1.16

# e.g., docker build -t my_docker .  --build-arg GENOME_BUILD=GRCh37 --build-arg SAMTOOLS_VERSION=1.9

FROM ubuntu:jammy-20211029

# =================================================
# install build dependencies
# =================================================
# git, maven, ant, emacs, cpanminus, pip
RUN apt-get update && apt-get install -y git maven ant emacs openjdk-11-jre-headless cpanminus python3-pip \ 
    # postgres client
    libpq-dev postgres-client-${POSTGRES_VERSION}  \
    # samtools dependencies, from https://github.com/chrishah/samtools-docker/blob/master/Dockerfile
	build-essential wget \
		libncurses5-dev zlib1g-dev libbz2-dev liblzma-dev libcurl3-dev \
    # seqrepo
    gcc tabix python3-dev \
    # clean up temp directories
	&& apt-get clean && apt-get purge && \
	rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# =================================================
# set JDK11 to default? not sure if necessary
# =================================================

# =================================================
# install preprocessing / loading dependencies
# samtools, htslib, vcftools, sqlite, BioPerl
# =================================================

# PERL Modules 
# -------------------------------------------------
# NOTE: this is an abbreviate list; will add to it as needed
# to avoid preloading unused dependencies

# BioPerl
RUN cpanm Bio Bio::DB::HTS Bio::EnsEMBL::XS Bio::Phylo \ 
# PostgreSQL
        DBI DBD::Pg JSON::XS \
# Other
        LWP LWP::Parallel \ 
        List::MoreUtils

# Python Modules 
# -------------------------------------------------
# NOTE this is an abbreviate list; will add to it as needed
# to avoid preloading unused dependencies
# hgvs --> maybe installed with ga4gh.vrs
RUN pip3 install --no-cache-dir  \
    pylint configparser \
    numpy pandas rpy2\
    psycopg2 \
    seqrepo bioutils ga4gh.vrs \ 
    pysam 

# samtools
# -------------------------------------------------
# adapted from https://github.com/chrishah/samtools-docker/blob/master/Dockerfile
WORKDIR /opt
RUN wget https://github.com/samtools/samtools/releases/download/${SAMTOOLS_VERSION}/samtools-${SAMTOOLS_VERSION}.tar.bz2 && \
	tar jxf samtools-${SAMTOOLS_VERSION}.tar.bz2 && \
	rm samtools-${SAMTOOLS_VERSION}.tar.bz2 && \
	cd samtools-${SAMTOOLS_VERSION} && \
	./configure --prefix $(pwd) && \
	make

# vcftools
# -------------------------------------------------
WORKDIR /opt
RUN git clone https://github.com/vcftools/vcftools.git && \
    cd vcftools && \
    ./autogen.sh && \
    ./configure && \
    make && make install 

ENV PERL5LIB=/opt/vcftools/src/perl/
# =================================================
# create user from config info / switch to user directory to build GUS
# =================================================
RUN useradd -ms /bin/bash ${USER}
USER ${USER}
WORKDIR /home/${USER}

ENV HOME=${WORKDIR}
ENV GUS_HOME=$HOME/gus_home
ENV PROJECT_HOME=$HOME/project_home

# build GUS environment
RUN mkdir -p ${GUS_HOME}/config ${PROJECT_HOME}
# checkout the git projects / based on version
# -------------------------------------------------
# build 

# update PATH
# ENV PATH=${PATH}:/opt/samtools-${SAMTOOLS_VERSION}
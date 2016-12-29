# miniconda is based on debian-jessie
FROM continuumio/miniconda3:4.1.11
MAINTAINER Brian Naughton

# -----------------------------------
# Install blast tools
#
RUN apt-get update && apt-get install -y \
  nano \
  ncbi-blast+


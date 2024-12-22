FROM ubuntu:oracular

# Set environment variables for versions
ARG HUGO_VERSION=0.139.2

COPY support/install_repo.sh /root/install_repo.sh
RUN chmod +x /root/install_repo.sh
RUN /root/install_repo.sh

# Install dependencies
RUN apt-get -y install ca-certificates openssl git curl wget

# Install dependencies
RUN apt-get -y install nodejs npm hugo
RUN apt-get -y install golang

# Export Go path
ENV PATH=$PATH:/usr/local/go/bin

WORKDIR /infrahouse-com
CMD ["hugo", "server", "--bind", "0.0.0.0", "--poll", "700ms"]

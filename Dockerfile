# Use the official Jenkins LTS image as a base
FROM jenkins/jenkins:2.504.1

# Maintainer information
LABEL maintainer="rajendra.daggubati1997@gmail.com" \
      version="2.504.2" \
      description="Jenkins with Docker support" \
      org.opencontainers.image.source="https://github.com/Chowdary1997/Jenkins_jenkins_nodes_Dockerfle.git" \
      org.opencontainers.image.licenses="MIT"

# Switch to root user to install Docker
USER root

# Install necessary packages for Docker
RUN apt-get update && \
    apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    maven \
    gnupg2 \
    lynis \
    colorized-logs \
    software-properties-common && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add - && \
    echo "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y docker-ce docker-ce-cli containerd.io && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*


# Add Jenkins user to the Docker group
RUN usermod -aG docker jenkins

# Healthcheck to ensure Jenkins is running
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:8080/login || exit 1

VOLUME /var/jenkins_home

# Switch back to the Jenkins user
USER jenkins
# Release ports 80 and 8080
EXPOSE 8080 80
# Start Jenkins
ENTRYPOINT ["/usr/local/bin/jenkins.sh"]



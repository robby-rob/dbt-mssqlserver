# 1. Download stage
# 1.1. Base
#ARG BASE_IMAGE=python:3.9.12-slim-buster
ARG BASE_IMAGE=python:3.9.12-slim-bullseye
FROM $BASE_IMAGE AS download_stage
WORKDIR /downloads
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg2 \
    lsb-release \
  && curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -

# 1.2. SQL Server ODBC driver
#ARG MSODBCSQL_PACKAGE=msodbcsql17
#ARG MSODBCSQL_RELEASE=17.8.1.1-1
ARG MSODBCSQL_PACKAGE=msodbcsql18
ARG MSODBCSQL_RELEASE=18.0.1.1-1
RUN RELEASE_DIST=$(lsb_release -is | awk '{print tolower($0)}') \
  && RELEASE_VER=$(lsb_release -rs) \
  && curl https://packages.microsoft.com/config/$RELEASE_DIST/$RELEASE_VER/prod.list > /etc/apt/sources.list.d/mssql-release.list \
  && apt-get update \
  && apt-get download $MSODBCSQL_PACKAGE=$MSODBCSQL_RELEASE \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 1.3. Azure CLI
#ARG AZURE_CLI=2.30.0
#RUN AZ_REPO=$(lsb_release -cs) \
#  && echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | tee /etc/apt/sources.list.d/azure-cli.list \
#  && apt-get update \
#  && AZURECLI=${AZURE_CLI}-1~${AZ_REPO} \
#  && apt-get download azure-cli=$AZURECLI

# 1.4. DBT Bash Autocompletion
RUN curl https://raw.githubusercontent.com/fishtown-analytics/dbt-completion.bash/master/dbt-completion.bash > ./dbt-completion.bash


# 2. Python stage
# 2.1. Base
FROM $BASE_IMAGE AS python_stage
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    unixodbc-dev \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
  && python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# 2.2. DBT with SQL Server support
ARG DBT_SQLSERVER=1.0.0
RUN python3 -m pip install -U pip \
  && pip install --upgrade \
    pip \
    setuptools \
  && pip install \
    dbt-sqlserver==$DBT_SQLSERVER


# 3. Final image
# 3.1. Base
FROM $BASE_IMAGE
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    git \
    bash-completion \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
  && python3 -m venv /opt/venv
#TODO: ADD root password
#TODO: ADD appuser group & user
ENV PATH="/opt/venv/bin:$PATH"

# 3.2. SQL Server ODBC driver
COPY --from=download_stage /downloads/$MSODBCSQL_PACKAGE* /tmp
RUN apt-get update \
  && apt-get dist-upgrade -y \
  && ACCEPT_EULA=Y apt-get install -y --no-install-recommends \
    /tmp/$MSODBCSQL_PACKAGE*.deb \
  && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 3.3. Azure CLI
#COPY --from=download_stage /downloads/azure-cli*.deb /tmp
#RUN apt-get update \
#  && apt-get install -y --no-install-recommends \
#    /tmp/azure-cli*.deb \
#  && rm -rf ./azure-cli \
#  && apt-get clean \
#   && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 3.4. Python venv
COPY --from=python_stage /opt/venv /opt/venv

# 3.5. DBT Bash Autocompletion
COPY --from=download_stage /downloads/dbt-completion.bash /tmp
RUN cp /tmp/dbt-completion.bash ~/.dbt-completion.bash \
  && echo 'source ~/.dbt-completion.bash' >> ~/.bash_profile \
  && rm -rf /tmp/*

# 3.6. Finish
ENV PYTHONIOENCODING=utf-8
ENV LANG C.UTF-8
WORKDIR /usr/app
ENTRYPOINT ["/bin/bash"]
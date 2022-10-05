# Contoso Project Name Generator application sample for Azure Kubernetes Service (AKS) developer experience

This project consists of a [frontend](https://github.com/sabbour/contoso-topics-frontend/) written in Node.JS and a [service](https://github.com/sabbour/contoso-topics-service) written in C# on top of .NET 6.

## Prerequisites
- Install the Azure CLI
- Authenticate using ``az login``
- Make sure you're executing against the right subscription using ``az account set --subscription <id>``

## Setup
- Run `./setup.sh` and provide the required parameters

## Post setup
- Follow setup steps at [frontend](https://github.com/sabbour/contoso-topics-frontend/) to deploy the frontend to the cluster
- Follow setup steps at [service](https://github.com/sabbour/contoso-topics-service/) to deploy the service to the cluster using the AKS developer experience tools
# Contoso project name generator for AKS developer experience demo

This project consists of a [frontend](https://github.com/sabbour/contoso-names-frontend/) written in Node.JS and a [service](https://github.com/sabbour/contoso-names-service) written in C# on top of .NET 6.

## Prerequisites
- Azure subscription
- Domain name to manage using Azure DNS

## Infrastructure setup
- Launch the [Azure Cloud Shell](https://shell.azure.com) and login with your Azure subscription.
- Clone this repository

    ```
    git clone https://github.com/sabbour/contoso-names.git
    ```

- Change into the `contoso-names` directory and run `setup.sh` while providing the required parameters. **Note:** Running this script will provision Azure resources that might incur billing.

    ```
    cd contoso-names
    chmod +x setup.sh
    ./setup.sh
    ```
    
    This will take a few minutes to complete and will provision an Azure Kubernetes Service (AKS) cluster with the recommended add-ons enabled, an Azure Container Registry, an Azure Key Vault with a self-signed certificate, an Azure DNS Zone. The script will also download the cluster's credentials into the cloud shell.

## Deploy the frontend
- Launch the [Azure Cloud Shell](https://shell.azure.com) and login with your Azure subscription.

- Clone the [frontend](https://github.com/sabbour/contoso-names-frontend/) repository.
    ```
    git clone https://github.com/sabbour/contoso-names-frontend.git
    ```

- Change into the `contoso-names-frontend` directory and deploy the Kubernetes manifests.
    ```
    cd contoso-names-frontend
    kubectl create namespace contoso-names
    kubectl apply -f ./manifests --namespace=contoso-names
    ```
- Give it a few minutes and retrieve the Kubernetes service's IP address.
    ```
    kubectl get service contoso-names-frontend --namespace=contoso-names -o jsonpath="{.status.loadBalancer.ingress[0].ip}"
    ```
- Now that you have the service's public IP address, navigate to [http://[contoso-frontend IP address]]() in your browser. The user interface will load but you will receive an error because the backend service hasn't been deployed yet.

    ![Screenshot of the broken frontend](img/frontend-broken.png)

## Iterate on the service
### Configure GitHub Codespaces
- Open the [service](https://github.com/sabbour/contoso-names-service/) repository with GitHub Codespaces. This will fork the repository under your profile.

    ![Create codespace](img/frontend-createcodespace.png)

    GitHub is going to build the codespace and in a few minutes you will be able to access it.

    ![Launching a codespace](img/launching-codespace.png)

### Login and select the Azure subscription

- Install the latest version of the [AKS Developer Tools extension](https://marketplace.visualstudio.com/items?itemName=ms-kubernetes-tools.aks-devx-tools), if it isn't already there.

    ![AKS Developer Experience extension](img/codespaces-extension.png)

- Launch the command palette (`Ctrl + Shift + P`) and run the `Azure: Sign in with Device Code` command to login to your Azure subscription.

    ![Sign in with Device Code](img/azure-sign-in.png)

- If you have access to multiple tenants, select the one you'd like to use by running the `Azure: Select Tenant` command.

    ![Select tenant](img/azure-select-tenant.png)

- Run the `Azure: Select Subscriptions` command to select the Azure subscription you'd like to use.

    ![Select subscription](img/azure-select-subs.png)

- Download the AKS cluster configuration on the Kubernetes extension page by clicking the Kubernetes icon on the left, then expand your Azure subscription to find your cluster. Right-click and select **Merge into Kubeconfig** to download the cluster credentials.

    ![Merge the AKS cluster kubeconfig](img/merge-kubeconfig.png)

### Launch the application in GitHub Codespaces
Hit `F5` to run the service in the codespace. This will build and launch the application in the codespace and tunnel the exposed endpoint back to your machine. You should now see the API endpoint.

![Screenshot of the Swagger API endpoint](img/service-swagger.png)

### Generate Dockerfile
Run the `AKS Developer: Draft a Dockerfile from source code` command.

![Draft a Dockerfile from source code](img/draft-docker.png)

Provide the following inputs to the command:
- **Source code location:** Select the `/workspaces/contoso-names-service`
- **Programming language:** C#
- **C# version:**  6.0
- **Port:** 80

This will generate an appropriate Dockerfile.

![Draft a Dockerfile from source code](img/dockercreate-results.png)

### Build the container image

To build the container image, you can either click the **Build container** button in the notification, or you can also run the `AKS Developer: Build a container with Azure Container Registry` command.

Provide the following inputs to the command:
- **Dockerfile location:** Select the `Dockerfile` file.
- **Tag image as:** `contoso-names-service:latest`
- **Registry provider:**  Connect to an Azure registry, then pick your Azure Container Registry from the list
- **Image base OS:** Linux

This will run a Docker build using Azure Container Registry.

![Docker build](img/dockerbuilding.png)

### Create a deployment and service

To deploy to Kubernetes, you need to have Kubernetes manifests for the deployment and service. You can either click the **Draft Kubernetes Deployment and Service** button in the notification, or you can also run the `AKS Developer: Draft a Kubernetes Deployment and Service` command.

Provide the following inputs to the command:
- **Output directory:** `/workspaces/contoso-names-service/manifests`.
- **Format:** Manifests
- **Kubernetes namespace:**  Create a new namespace `contoso-names` and select it
- **Application name:** `contoso-names-service`
- **Image type:** Azure Container Registry
- **Resource group:** Select the resource group of the Azure Container Registry
- **Container registry:** Select the registry that you used to build the image
- **Repository:** Type in the image name `contoso-names-service`
- **Tag:** Type in `latest`
- **Port:** 80

This will generate **deployment.yaml** and **service.yaml** files.

![Generated deployment and service](img/deployment-service.png)

Edit the **service.yaml** file to change the load balancer type to `ClusterIP` since the frontend app will be calling this API over the internal DNS name.

![Change load balancer type to ClusterIP](img/clusterip.png)

To deploy to Kubernetes, you can either click the **Deploy** button in the notification, or you can also run the `kubectl apply -f ./manifests` in the terminal.

![Run kubectl apply](img/kubectlapply.png)

### Review that the frontend app is  working (and buggy)

Using the frontend app's service IP, open that in the browser again and you should see the app is now working. But there is a bug. It seems that there is some repetition in the generated names.

![Run kubectl apply](img/namesapp-bug.png)

### Debug with Bridge to Kubernetes

To debug where is this repetition in the generated name is coming from, you will use Bridge to Kubernetes to attach a debugger to the deployed application on the Kubernetes cluster. Note that you should only do this on a non-production deployment. Since this is the team's AKS development cluster, you should be ok here.

To use the Bridge to Kubernetes extension, you need to switch your Kubernetes cluster context to use the namespace which contains the service you want to debug. Click on **default** in the bottom tabs and type in `contoso-names` in the command palette that will popup.

![Configure namespace](img/bridge-configure-namespace.png)

Launch the command palette again and run the `Bridge to Kubernetes: Configure` command.

![Bridge to Kubernetes configure command](img/bridge-configure-command.png)

Provide the following inputs to the command:
- **Service to redirect:** `contoso-names-service`.
- **Local port:** 8080
- **Launch configuration:**  Choose the `.NET Core Launch (web)` configuration
- **Isolation:** Choose **No** to not isolate the traffic of your local version of the service from other developers on the cluster.

The extension will create a new launch configuration called **.NET Core Launch (web) with Kubernetes**. Make sure to switch to that configuration.

![Select the Bridge to Kubernetes launch configuration](img/bridge-launch-config.png)

Place a breakpoint in **Program.cs** and hit `F5` to run the service in the codespace with the Bridge to Kubernetes debug launch configuration. Refresh the frontend app and you should see your breakpoint being hit.

![Bridge to Kubernetes breakpoint hit](img/bridge-breakpoint.png)

You realize that you are referring to the *adjective* twice in the returned string. You stop the debugger and quickly fix that bug by referring to the *noun* the second time.

![Codefix](img/bridge-codefix.png)

You hit `F5` one more time to run your code that you just edited in GitHub Codespaces in the AKS cluster. Note that you didn't have to rebuild a Docker container, push it to a registry, or mess around with YAML files. You quickly see that your change fixes the problem.

![Working application](img/namesapp-working.png)

You are now ready to commit this bug fix.

### Create a GitHub Actions workflow

## Configure Web Application Routing on the frontend
# Steps to deploy Ingress

## Preparation

1. Download yaml file
2. Comment "Annotations" inside "Metadata"

   ```
   annotations:
   kubernetes.io/ingress.global-static-ip-name:ingress-sie-impresordigital
   networking.gke.io/v1.FrontendConfig:http-redirect-config


   ```
3. Connect to the cluster
4. Apply the yaml with kubectl apply -f
5. Wait for the ingress to come up on green
6. Wait for the ip of the ingress to show up
7. Reserve and Assing the ip as Static using the name of the annotations

   ```
   annotations:
   kubernetes.io/ingress.global-static-ip-name:ingress-sie-impresordigital
   networking.gke.io/v1.FrontendConfig:http-redirect-config
   ```
8. Once the static ip is assigned create a Loadbalancer front end for http
9.

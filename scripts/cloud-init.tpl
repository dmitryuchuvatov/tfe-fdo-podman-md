#cloud-config
write_files:
  - path: /var/tmp/kube.yaml
    permissions: '0640'
    content: |
      apiVersion: "v1"
      kind: "Pod"
      metadata:
        labels:
          app: "terraform-enterprise"
        name: "terraform-enterprise"
      spec:
        restartPolicy: "Never"
        containers:
        - env:
          - name: "TFE_OPERATIONAL_MODE"
            value: "disk"
          - name: "TFE_LICENSE"
            value: "${tfe_license}"
          - name: "TFE_HTTP_PORT"
            value: "8080"
          - name: "TFE_HTTPS_PORT"
            value: "8443"
          - name: "TFE_HOSTNAME"
            value: "${route53_subdomain}.${route53_zone}"
          - name: "TFE_TLS_CERT_FILE"
            value: "/etc/ssl/private/terraform-enterprise/cert.pem"
          - name: "TFE_TLS_KEY_FILE"
            value: "/etc/ssl/private/terraform-enterprise/key.pem"
          - name: "TFE_TLS_CA_BUNDLE_FILE"
            value: "/etc/ssl/private/terraform-enterprise/bundle.pem"
          - name: "TFE_DISK_CACHE_VOLUME_NAME"
            value: "terraform-enterprise_terraform-enterprise-cache"
          - name: "TFE_LICENSE_REPORTING_OPT_OUT"
            value: "true"
          - name: "TFE_ENCRYPTION_PASSWORD"
            value: "${tfe_password}"
          image: "images.releases.hashicorp.com/hashicorp/terraform-enterprise:${tfe_release}"
          name: "terraform-enterprise"
          ports:
          - containerPort: 8080
            hostPort: 80
          - containerPort: 8443
            hostPort: 443
          - containerPort: 9090
            hostPort: 9090
          securityContext:
            capabilities:
              add:
              - "CAP_IPC_LOCK"
            readOnlyRootFilesystem: true
            seLinuxOptions:
              type: "spc_t"
          volumeMounts:
          - mountPath: "/etc/ssl/private/terraform-enterprise"
            name: "certs"
          - mountPath: "/var/log/terraform-enterprise"
            name: "log"
          - mountPath: "/run"
            name: "run"
          - mountPath: "/tmp"
            name: "tmp"
          - mountPath: "/var/lib/terraform-enterprise"
            name: "data"
          - mountPath: "/run/docker.sock"
            name: "docker-sock"
          - mountPath: "/var/cache/tfe-task-worker/terraform"
            name: "terraform-enterprise_terraform-enterprise-cache-pvc"
        volumes:
        - hostPath:
            path: "/opt/fdo/certs"
            type: "Directory"
          name: "certs"
        - emptyDir:
            medium: "Memory"
          name: "log"
        - emptyDir:
            medium: "Memory"
          name: "run"
        - emptyDir:
            medium: "Memory"
          name: "tmp"
        - hostPath:
            path: "/opt/fdo/data"
            type: "Directory"
          name: "data"
        - hostPath:
            path: "/var/run/docker.sock"
            type: "File"
          name: "docker-sock"
        - name: "terraform-enterprise_terraform-enterprise-cache-pvc"
          persistentVolumeClaim:
            claimName: "terraform-enterprise_terraform-enterprise-cache"

  - path: /var/tmp/podman.sh 
    permissions: '0750'
    content: |
      #!/usr/bin/env bash
      dnf install -y container-tools
      systemctl enable --now podman.socket

  - path: /var/tmp/certificates.sh 
    permissions: '0750'
    content: |
      #!/usr/bin/env bash
      
      # Create folders for FDO installation, TLS certificates and data
      mkdir /opt/fdo
      mkdir /opt/fdo/certs
      mkdir /opt/fdo/data

      # Install unzip command 
      dnf install unzip -y 
      
      # Install AWS CLI
      pushd /var/tmp
      curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
      unzip awscliv2.zip
      sudo ./aws/install --bin-dir /usr/bin --install-dir /usr/local/aws-cli --update

      # Prepare certificates
      aws s3 cp s3://${environment_name}-filesbucket/fullchain.pem /var/tmp/cert.pem
      aws s3 cp s3://${environment_name}-filesbucket/fullchain.pem /var/tmp/bundle.pem
      aws s3 cp s3://${environment_name}-filesbucket/key.pem /var/tmp/key.pem

      cp /var/tmp/cert.pem /opt/fdo/certs/cert.pem
      cp /var/tmp/bundle.pem /opt/fdo/certs/bundle.pem 
      cp /var/tmp/key.pem /opt/fdo/certs/key.pem
   
  - path: /var/tmp/tfe.sh   
    permissions: '0750'
    content: |
      #!/usr/bin/env bash    

      # Copy the YAML config to install path
      cp /var/tmp/kube.yaml /opt/fdo/
      pushd /opt/fdo/

      # Authenticate to container registry 
      echo "${tfe_license}" | podman login --username terraform images.releases.hashicorp.com --password-stdin
      
      # Deploy TFE
      podman play kube /opt/fdo/kube.yaml

runcmd:
  - sudo bash /var/tmp/podman.sh 
  - sudo bash /var/tmp/certificates.sh
  - sudo bash /var/tmp/tfe.sh
# Deploying the backend

The API runs on the Docker Swarm cluster as the Portainer stack **flowmate**, set up the same way as liloxi: the stack file is [`deploy/portainer.yaml`](../deploy/portainer.yaml) in git, and the Release workflow updates it.

What the stack runs: `postgres` (16, data in the `postgres_data` volume), `api` (behind Traefik, Let's Encrypt), and `backup` (`swarm-maintenance`: `pg_dump` to Azure Blob at 02:00 and 14:00, prefix `flowmate`).

## One-time setup

1. **Database password**, as a Swarm secret (on a manager node):
   ```bash
   openssl rand -base64 32 | tr -d '\n' | docker secret create flowmate_postgres_password -
   ```
   `azure_storage_account` and `azure_storage_key` already exist on the cluster (liloxi uses them).
2. **DNS:** point `todo.asem-mkl.com` at the cluster, like the liloxi hosts. The domain is written in the Traefik rule in `deploy/portainer.yaml`; change it there to move the API.
3. **Portainer:** Stacks › Add stack › Repository.
   - Repository `https://github.com/as206em/FlowMate`, reference `refs/heads/main`, compose path `deploy/portainer.yaml`. Add credentials if the repository is private.
   - Turn on **GitOps updates › Webhook** and copy the webhook URL.
   - The image is `ghcr.io/as206em/flowmate-api`. While the GHCR package is private, add a ghcr.io registry in Portainer (Registries) with a GitHub token that can read packages. Alternatively make the package public in its GitHub package settings.
4. **GitHub secret** (Settings › Secrets and variables › Actions): `PORTAINER_WEBHOOK` = the webhook URL.
5. **First deploy:** Actions › Release › Run workflow › tick **api**. The image has to exist before the stack can start the API.

The deploy job commits the new image tag to `main` (`deploy: update selected images to sha-…`). If `main` is protected, allow GitHub Actions to push to it.

## Each deploy

Actions › **Release** › tick **api** (or **all**) › Run workflow:

1. `backend_test`: typecheck and tests.
2. `build_images`: builds `services/api/Dockerfile` and pushes `ghcr.io/as206em/flowmate-api:sha-<commit>` and `:latest`.
3. `deploy`: writes `sha-<commit>` into `deploy/portainer.yaml`, commits to `main` and calls `PORTAINER_WEBHOOK`. Portainer pulls the stack file and rolls the API, starting the new copy before stopping the old one.

The API runs its database migrations on start. To roll back, revert the deploy commit (the image tag) and call the webhook, or redeploy the stack in Portainer. A migration is not undone by rolling back the image, so keep schema changes backward compatible.

## First account

```bash
docker exec -it $(docker ps -qf name=flowmate_api) node dist/cli.js create-user --name "Asem" --email you@example.com --device "MacBook"
```

It prints the token once. In FlowMate › Settings › Cloud sync, enter server `https://todo.asem-mkl.com` and the token, then turn sync on. For another Mac: `create-token --user you@example.com --device "iMac"`.

## Check it

```bash
curl https://todo.asem-mkl.com/health/ready
```

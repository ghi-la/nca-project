# Neural Code Analysis - Project

> Authors: Ghilardini Matteo, Toscano Sasha

## Quick Start

- Enable USI-VPN
- Connect to the server via SSH:

```bash
ssh <short>.usi.ch@@bre.usi.ch
```

- Ask Sasha to access folder (Matteo has no access to it):

```bash
/scratch/nca-course/toscas/
```

- Sync local folder with home folder on server:

```bash
rsync -avz --exclude .git --exclude .venv ./scratch/ <user>@usi.ch@bre.usi.ch:~/scratch/
```

- Sync local folder with actual scratch folder on server:

```bash
rsync -avz --exclude .git --exclude .venv ./scratch/ <user>@usi.ch@bre.usi.ch:/scratch/nca-course/$USER
```

- Load the OpenAI API key (server or client, as you need):
```bash
echo 'export OPENAI_API_KEY=<your_api_key>' > ~/.nca_openai
chmod 600 ~/.nca_openai
source ~/.nca_openai
```

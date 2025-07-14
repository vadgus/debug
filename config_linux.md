```
curl -fsSL -H 'Cache-Control: no-cache' https://raw.githubusercontent.com/vadgus/debug/refs/heads/main/config_linux.sh | sudo bash
```

```
echo -e '#!/bin/sh\ncurl -fsSL -H "Cache-Control: no-cache" https://raw.githubusercontent.com/vadgus/debug/refs/heads/main/config_linux.sh | sudo bash\nreboot' > install.sh && chmod +x install.sh
```

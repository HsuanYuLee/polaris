# a local config added the way the repo already does configs: one more JSON file for the existing loader
git branch -M main
mkdir -p config internal/config
for env in dev stage prod; do printf '{ "port": 8080, "env": "%s" }\n' $env > config/$env.json; done
cat > internal/config/load.go <<'GO'
package config

import ("encoding/json"; "os")

type Config struct { Port int `json:"port"`; Env string `json:"env"` }

func Load(path string) (Config, error) {
	var c Config
	b, err := os.ReadFile(path)
	if err != nil { return c, err }
	return c, json.Unmarshal(b, &c)
}
GO
printf 'module example.com/svc\n\ngo 1.22\n' > go.mod
git add -A && git commit -qm "service config loading"
git checkout -q -b feat/change
printf '{ "port": 9090, "env": "local" }\n' > config/local.json
git add -A && git commit -qm "local config for running the service on a laptop"

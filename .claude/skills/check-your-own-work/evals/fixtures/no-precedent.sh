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
printf 'port: 9090\nenv: local\nfeature_flags:\n  - fast_path\n' > config/local.yaml
cat > internal/config/yaml.go <<'GO'
package config

import ("bufio"; "os"; "strconv"; "strings")

// LoadYAML parses the small subset of YAML our local config uses: key: value pairs and one level of lists.
func LoadYAML(path string) (Config, map[string][]string, error) {
	var c Config
	lists := map[string][]string{}
	f, err := os.Open(path)
	if err != nil { return c, nil, err }
	defer f.Close()
	var current string
	s := bufio.NewScanner(f)
	for s.Scan() {
		line := s.Text()
		if strings.HasPrefix(line, "  - ") { lists[current] = append(lists[current], strings.TrimPrefix(line, "  - ")); continue }
		k, v, ok := strings.Cut(line, ":")
		if !ok { continue }
		v = strings.TrimSpace(v)
		switch k {
		case "port": c.Port, _ = strconv.Atoi(v)
		case "env": c.Env = v
		default: current = k
		}
	}
	return c, lists, s.Err()
}
GO
git add -A && git commit -qm "local config in YAML with feature flags"

package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

// NewRunnerPortFromEnv は RUNNER_PORT を読み、broker が runner の管理 API に接続するための port を返す。
// 応答ヘッダには含めないが、broker/healthcheck が `http://<host>:<RUNNER_PORT>/health` を叩くため必須。
// 未設定 / 非整数 / 範囲外はいずれもエラーで返し、既定値には落とさない。
func NewRunnerPortFromEnv() (int, error) {
	raw := strings.TrimSpace(os.Getenv("RUNNER_PORT"))
	if raw == "" {
		return 0, fmt.Errorf("missing required environment variable: RUNNER_PORT")
	}
	port, err := strconv.Atoi(raw)
	if err != nil {
		return 0, fmt.Errorf("RUNNER_PORT %q must be an integer: %w", raw, err)
	}
	if port <= 0 || port > 65535 {
		return 0, fmt.Errorf("RUNNER_PORT %d must be between 1 and 65535", port)
	}
	return port, nil
}

package config

import (
	"fmt"
	"os"
	"strings"

	"github.com/ogadra/bunshin/broker/handler"
)

// StackConfig は broker 自身の stack 識別子と fallback 転送先を保持する。
type StackConfig struct {
	// Self は自 stack 名。session ID の prefix にも使われる。
	Self string
	// Fallbacks は BUNSHIN_STACKS から Self を除いた転送候補。空の場合は fallback を発行しない。
	Fallbacks []string
}

// NewStackFromEnv は STACK_NAME と BUNSHIN_STACKS を読んで StackConfig を組み立てる。
// STACK_NAME と BUNSHIN_STACKS は必須で、STACK_NAME は BUNSHIN_STACKS に列挙されている必要がある。
func NewStackFromEnv() (StackConfig, error) {
	self := os.Getenv("STACK_NAME")
	if self == "" {
		return StackConfig{}, fmt.Errorf("missing required environment variable: STACK_NAME")
	}
	rawList := os.Getenv("BUNSHIN_STACKS")
	if rawList == "" {
		return StackConfig{}, fmt.Errorf("missing required environment variable: BUNSHIN_STACKS")
	}
	if !stackListed(rawList, self) {
		return StackConfig{}, fmt.Errorf("STACK_NAME %q is not listed in BUNSHIN_STACKS %q", self, rawList)
	}
	return StackConfig{
		Self:      self,
		Fallbacks: handler.FallbackStacksFromStackList(rawList, self),
	}, nil
}

func stackListed(rawList, self string) bool {
	for _, s := range strings.Split(rawList, ",") {
		if strings.TrimSpace(s) == self {
			return true
		}
	}
	return false
}

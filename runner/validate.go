package main

import (
	"regexp"
	"strings"
)

// whitelistedBareCommands is the set of commands that are allowed without LLM
// validation only when invoked with no arguments.
var whitelistedBareCommands = map[string]bool{
	"pwd":      true,
	"date":     true,
	"whoami":   true,
	"env":      true,
	"tree":     true,
	"id":       true,
	"hostname": true,
	"uptime":   true,
	"df":       true,
	"free":     true,
	"ps":       true,
	"history":  true,
}

// whitelistedPrefixCommands is the set of commands that are allowed without LLM
// validation when invoked bare or with arguments, as long as no shell
// metacharacters are present. This is the same pattern used for "which".
var whitelistedPrefixCommands = map[string]bool{
	"cd":       true,
	"echo":     true,
	"cat":      true,
	"head":     true,
	"tail":     true,
	"grep":     true,
	"find":     true,
	"ls":       true,
	"uname":    true,
	"wc":       true,
	"file":     true,
	"du":       true,
	"stat":     true,
	"realpath": true,
	"printf":   true,
}

// whitelistedExactCommands is the set of full command strings including arguments
// that are allowed without LLM validation. Unlike whitelistedBareCommands which
// matches bare commands only, these match the entire trimmed command string exactly.
var whitelistedExactCommands = map[string]bool{
	"home-manager switch --rollback":                                     true,
	"home-manager generations":                                           true,
	`nix develop --command sh -c "figlet 'Nix' | cowsay -n | lolcat -f"`: true,
}

// shellMetaChars matches shell operators that could be used to chain commands.
var shellMetaChars = regexp.MustCompile(`[;|&<>\t\n\r` + "`" + `]|\$\(`)

// classifyCommand returns the classification of a command for audit logging.
// It returns "whitelisted" if the trimmed command exactly matches a bare
// whitelisted command, or if it is a "nix run nixpkgs#..." invocation
// without shell metacharacters. Otherwise it returns "validated".
func classifyCommand(cmd string) string {
	trimmed := strings.TrimSpace(cmd)
	if whitelistedBareCommands[trimmed] {
		return "whitelisted"
	}
	if whitelistedExactCommands[trimmed] {
		return "whitelisted"
	}
	for prefix := range whitelistedPrefixCommands {
		if (trimmed == prefix || strings.HasPrefix(trimmed, prefix+" ")) && !shellMetaChars.MatchString(trimmed) {
			return "whitelisted"
		}
	}
	if strings.HasPrefix(trimmed, "which ") && !shellMetaChars.MatchString(trimmed) {
		return "whitelisted"
	}
	if strings.HasPrefix(trimmed, "nix run nixpkgs#") && !shellMetaChars.MatchString(trimmed) {
		return "whitelisted"
	}
	return "validated"
}

package network

import "testing"

func TestConfiguredChunksPerUpdateUsesDefault(t *testing.T) {
	t.Setenv(chunksPerUpdateEnv, "")

	if got := configuredChunksPerUpdate(); got != defaultChunksPerUpdate {
		t.Fatalf("configuredChunksPerUpdate() = %d, want %d", got, defaultChunksPerUpdate)
	}
}

func TestConfiguredChunksPerUpdateUsesEnvOverride(t *testing.T) {
	t.Setenv(chunksPerUpdateEnv, "48")

	if got := configuredChunksPerUpdate(); got != 48 {
		t.Fatalf("configuredChunksPerUpdate() = %d, want 48", got)
	}
}

func TestConfiguredChunksPerUpdateIgnoresInvalidEnv(t *testing.T) {
	for _, value := range []string{"0", "-2", "nope"} {
		t.Run(value, func(t *testing.T) {
			t.Setenv(chunksPerUpdateEnv, value)

			if got := configuredChunksPerUpdate(); got != defaultChunksPerUpdate {
				t.Fatalf("configuredChunksPerUpdate() = %d, want %d", got, defaultChunksPerUpdate)
			}
		})
	}
}

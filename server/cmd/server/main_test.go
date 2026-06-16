package main

import "testing"

func TestConfiguredServerAddressDefaultsToLoopback(t *testing.T) {
	t.Setenv("RUMPELMC_SERVER_ADDRESS", "")

	got := configuredServerAddress()
	want := "127.0.0.1:25565"
	if got != want {
		t.Fatalf("configuredServerAddress() = %q, want %q", got, want)
	}
}

func TestConfiguredServerAddressUsesExplicitOverride(t *testing.T) {
	t.Setenv("RUMPELMC_SERVER_ADDRESS", "0.0.0.0:25565")

	got := configuredServerAddress()
	want := "0.0.0.0:25565"
	if got != want {
		t.Fatalf("configuredServerAddress() = %q, want %q", got, want)
	}
}

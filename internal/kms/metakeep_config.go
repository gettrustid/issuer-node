package kms

import (
	"os"
)

type MetaKeepConfig struct {
	BjjAppApiKey    string `tip:"MetaKeep BJJ app API key"`
	BjjAppApiSecret string `tip:"MetaKeep BJJ app API secret"`
}

// TODO: revist switching out env
func LoadMetaKeepConfig() *MetaKeepConfig {
	return &MetaKeepConfig{
		BjjAppApiKey:    os.Getenv("METAKEEP_BJJ_API_KEY"),
		BjjAppApiSecret: os.Getenv("METAKEEP_BJJ_API_SECRET"),
	}
}

package kms

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"strings"
	"time"

	"golang.org/x/exp/slog"

	"github.com/hashicorp/vault/api"
	"github.com/iden3/go-iden3-core/v2/w3c"
	"github.com/iden3/go-iden3-crypto/utils"
)

type metakeepBJJKeyProvider struct {
	keyType   KeyType
	apiKey    string
	apiSecret *ecdsa.PrivateKey

	bjjPublicKeyHex string
	bjjPublicKey    []byte

	identity *w3c.DID
}

const (
	metakeepApiHost     = "api.metakeep.xyz"
	metakeepApiEndpoint = "https://" + metakeepApiHost
	getPublicKeyUrl     = metakeepApiEndpoint + "/v3/getDeveloperWallet"
	signatureUrl        = metakeepApiEndpoint + "/v2/app/sign/message"
	requestMethod       = "POST"
)

// NewMetaKeepBJJKeyProvider creates new key provider for BabyJubJub keys stored
// in MetaKeep hardware wallet infrastructure,
func NewMetaKeepBJJKeyProvider(config *MetaKeepConfig) KeyProvider {
	slog.Info("MetaKeep BJJ Provider: NewMetaKeepBJJKeyProvider()")

	if config.BjjAppApiKey == "" {
		panic("Metakeep BJJ Provider: empty apiKey")
	}

	if config.BjjAppApiSecret == "" {
		panic("Metakeep BJJ Provider: empty apiSecret")
	}

	// Build the private key
	paddedB64Secret := config.BjjAppApiSecret + strings.Repeat("=", 4-len(config.BjjAppApiSecret)%4)
	privateKeyBytes, err := base64.URLEncoding.DecodeString(paddedB64Secret)

	if err != nil {
		panic(fmt.Sprintf("MetaKeep BJJ Provider: Failed to decode MetaKeepBjjProvider api secret: %s", err))
	}

	privateKey := new(ecdsa.PrivateKey)
	privateKey.Curve = elliptic.P256()
	privateKey.D = new(big.Int).SetBytes(privateKeyBytes)

	return &metakeepBJJKeyProvider{
		keyType:   KeyTypeBabyJubJub,
		apiKey:    config.BjjAppApiKey,
		apiSecret: privateKey,
	}
}

// LinkToIdentity implements KeyProvider.
func (m *metakeepBJJKeyProvider) LinkToIdentity(ctx context.Context, keyID KeyID, identity w3c.DID) (KeyID, error) {
	slog.Info("MetaKeep BJJ Provider: LinkToIdentity()")
	slog.Warn("MetaKeep does not support LinkToIdentity. This is a no-op")

	var err error
	if err = m.validateKeyID(keyID); err != nil {
		return keyID, err
	}

	// Copy the identity and store it in the provider
	m.identity, err = w3c.ParseDID(identity.String())

	if err != nil {
		return keyID, err
	}

	return keyID, nil
}

// ListByIdentity implements KeyProvider.
func (m *metakeepBJJKeyProvider) ListByIdentity(ctx context.Context, identity w3c.DID) ([]KeyID, error) {
	slog.Info("MetaKeep BJJ Provider: ListByIdentity()")

	// Make sure identity is the same as the one linked to this provider
	if m.identity != nil && m.identity.String() != identity.String() {
		return nil, errors.New("provided identity does not match the identity linked to this provider")
	}

	currentKeyId, err := m.getKeyID()

	if err != nil {
		return nil, err
	}

	return []KeyID{currentKeyId}, nil
}

// New implements KeyProvider.
func (m *metakeepBJJKeyProvider) New(identity *w3c.DID) (KeyID, error) {
	slog.Info("MetaKeep BJJ Provider: New()")

	// MetaKeep does not support binding to an identity
	if identity != nil {
		return KeyID{}, errors.New("MetaKeep does not support binding to an existing identity. w3c.DID must be nil")
	}

	// We return KeyID for the public key corresponding to MetaKeep BJJ hardware wallet app.
	return m.getKeyID()
}

// PublicKey implements KeyProvider.
func (m *metakeepBJJKeyProvider) PublicKey(keyID KeyID) ([]byte, error) {
	slog.Info("MetaKeep BJJ Provider: PublicKey()")

	if keyID.Type != m.keyType {
		return nil, ErrIncorrectKeyType
	}

	if m.bjjPublicKey != nil {
		return m.bjjPublicKey, nil
	}

	// Call MetaKeep API to get the public key
	var resJson struct {
		Wallet struct {
			PublicKey string `json:"publicKey"`
		} `json:"wallet"`
	}
	err := m.metakeepHttpRequest(getPublicKeyUrl, nil, &resJson)
	if err != nil {
		return nil, err
	}

	// Decode the public key
	publicKey, err := hex.DecodeString(resJson.Wallet.PublicKey[2:])
	if err != nil {
		return nil, err
	}

	m.bjjPublicKeyHex = resJson.Wallet.PublicKey
	m.bjjPublicKey = publicKey

	return publicKey, nil
}

// Sign implements KeyProvider.
func (m *metakeepBJJKeyProvider) Sign(ctx context.Context, keyID KeyID, data []byte) ([]byte, error) {
	slog.Info("MetaKeep BJJ Provider: Sign()")

	if err := m.validateKeyID(keyID); err != nil {
		return nil, err
	}

	if len(data) > 32 {
		return nil, errors.New("data to sign is too large")
	}

	i := new(big.Int).SetBytes(utils.SwapEndianness(data))
	if !utils.CheckBigIntInField(i) {
		return nil, errors.New("data to sign is too large")
	}

	// MetaKeep expects bigint to be sent as a big-endian hex string
	dataHex := "0x" + hex.EncodeToString(utils.SwapEndianness(data))

	// Construct the request
	payload := map[string]string{
		"message": dataHex,
		// Signing reason. This can be customized to your application.
		"reason": "create a verified credential",
	}

	var resJson struct {
		Signature string `json:"signature"`
	}

	err := m.metakeepHttpRequest(signatureUrl, payload, &resJson)

	if err != nil {
		return nil, err
	}

	// Decode the signature
	signature, err := hex.DecodeString(resJson.Signature[2:])

	if err != nil {
		return nil, err
	}

	return signature, nil
}

func (m *metakeepBJJKeyProvider) metakeepHttpRequest(url string, jsonPayload any, jsonRes any) error {
	body := bytes.NewBuffer([]byte{})

	if jsonPayload != nil {
		payload, err := json.Marshal(jsonPayload)

		if err != nil {
			return err
		}

		body = bytes.NewBuffer(payload)
	}

	req, err := http.NewRequest(requestMethod, url, body)
	if err != nil {
		return err
	}

	timestampMillis := time.Now().UnixNano() / int64(time.Millisecond)
	apiSignature, err := m.generateAPISignature(requestMethod, strings.TrimPrefix(url, metakeepApiEndpoint), "", timestampMillis, body.String())

	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-API-Key", m.apiKey)
	req.Header.Set("X-Timestamp", fmt.Sprintf("%d", timestampMillis))
	req.Header.Set("X-API-Signature", apiSignature)

	res, err := http.DefaultClient.Do(req)

	// Check for non-200 status code
	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("MetaKeep API returned non-200 status code: %d", res.StatusCode)
	}

	if err != nil {
		return err
	}

	// Parse the JSON response
	err = json.NewDecoder(res.Body).Decode(jsonRes)
	if err != nil {
		return err
	}

	return nil
}

func (m *metakeepBJJKeyProvider) generateAPISignature(httpMethod, apiPath, idempotencyKey string, timestampMillis int64, requestDataString string) (string, error) {
	// Build the string to sign
	hostElement := fmt.Sprintf("%s\n", metakeepApiHost)
	methodElement := fmt.Sprintf("%s\n", httpMethod)
	pathElement := fmt.Sprintf("%s\n", apiPath)
	idempotencyElement := ""
	if idempotencyKey != "" {
		idempotencyElement = fmt.Sprintf("Idempotency-Key:%s\n", idempotencyKey)
	}
	timestampElement := fmt.Sprintf("X-Timestamp:%d\n", timestampMillis)
	dataElement := requestDataString

	hashedRequest := sha256.Sum256([]byte(strings.Join([]string{hostElement, methodElement, pathElement, idempotencyElement, timestampElement, dataElement}, "")))

	// Sign the request
	signingHashedInput := sha256.Sum256([]byte(hashedRequest[:]))
	r, s, err := ecdsa.Sign(rand.Reader, m.apiSecret, signingHashedInput[:])

	if err != nil {
		return "", fmt.Errorf("failed to Sign MetaKeepBjjProvider request: %s", err)
	}

	// Signature is 64 bytes concatenated R and S values
	// R and S are converted to big-endian 32-byte values and concatenated
	signature := append(r.FillBytes(make([]byte, 32)), s.FillBytes(make([]byte, 32))...)

	return base64.StdEncoding.EncodeToString(signature), nil
}

func (m *metakeepBJJKeyProvider) validateKeyID(keyID KeyID) error {
	currentKeyId, err := m.getKeyID()

	if err != nil {
		return err
	}

	if keyID != currentKeyId {
		return errors.New("provided keyID is not known to this provider")
	}

	return nil
}

func (m *metakeepBJJKeyProvider) getKeyID() (KeyID, error) {
	// Make sure public key is available
	_, err := m.PublicKey(KeyID{Type: m.keyType})

	if err != nil {
		return KeyID{}, err
	}

	return KeyID{
		Type: m.keyType,
		ID:   string(m.keyType) + ":" + m.bjjPublicKeyHex,
	}, nil
}

// Open returns an initialized KMS
// - For BJJ keys, it replaces the default BJJ key provider with MetaKeep hardware wallet BJJ key provider.
// - For Ethereum keys, currently it uses the default Vault plugin-iden3 key provider.
// TOD: Replace with MetaKeep hardware wallet Ethereum key provider
func OpenKMS(config *MetaKeepConfig, pluginIden3MountPath string, vault *api.Client) (*KMS, error) {
	// Create MetaKeep BJJ key provider
	bjjKeyProvider := NewMetaKeepBJJKeyProvider(config)

	// Create Ethereum key provider
	// TODO: Replace with MetaKeep hardware wallet Ethereum key provider
	ethKeyProvider, err := NewVaultPluginIden3KeyProvider(vault, pluginIden3MountPath, KeyTypeEthereum)
	if err != nil {
		return nil, fmt.Errorf("cannot create Ethereum key provider: %+v", err)
	}

	keyStore := NewKMS()
	err = keyStore.RegisterKeyProvider(KeyTypeBabyJubJub, bjjKeyProvider)
	if err != nil {
		return nil, fmt.Errorf("cannot register BabyJubJub key provider: %+v", err)
	}

	err = keyStore.RegisterKeyProvider(KeyTypeEthereum, ethKeyProvider)
	if err != nil {
		return nil, fmt.Errorf("cannot register Ethereum key provider: %+v", err)
	}

	return keyStore, nil
}

// Delete implements KeyProvider.
func (m *metakeepBJJKeyProvider) Delete(ctx context.Context, keyID KeyID) error {
	panic("unimplemented")
}

// Exists implements KeyProvider.
func (m *metakeepBJJKeyProvider) Exists(ctx context.Context, keyID KeyID) (bool, error) {
	// Check if the keyID matches the current MetaKeep pubkey
	currentKeyId, err := m.getKeyID()
	if err != nil {
		return false, err
	}
	return keyID == currentKeyId, nil
}

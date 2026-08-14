package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"sync"
	"time"
)

const caDir = "ca"

type certManager struct {
	caCert *x509.Certificate
	caKey  *rsa.PrivateKey

	mu    sync.Mutex
	cache map[string]*tls.Certificate
}

func newCertManager() (*certManager, error) {
	cm := &certManager{cache: make(map[string]*tls.Certificate)}
	if err := cm.ensureCA(); err != nil {
		return nil, fmt.Errorf("ensure CA: %w", err)
	}
	return cm, nil
}

func (cm *certManager) caPaths() (certPath, keyPath string) {
	return filepath.Join(caDir, "ca.crt"), filepath.Join(caDir, "ca.key")
}

func (cm *certManager) ensureCA() error {
	if err := os.MkdirAll(caDir, 0700); err != nil {
		return err
	}
	certPath, keyPath := cm.caPaths()

	if fileExists(certPath) && fileExists(keyPath) {
		return cm.loadCA(certPath, keyPath)
	}
	return cm.generateCA(certPath, keyPath)
}

func (cm *certManager) loadCA(certPath, keyPath string) error {
	certPEM, err := os.ReadFile(certPath)
	if err != nil {
		return err
	}
	keyPEM, err := os.ReadFile(keyPath)
	if err != nil {
		return err
	}

	certBlock, _ := pem.Decode(certPEM)
	if certBlock == nil {
		return fmt.Errorf("invalid CA cert PEM at %s", certPath)
	}
	cert, err := x509.ParseCertificate(certBlock.Bytes)
	if err != nil {
		return err
	}

	keyBlock, _ := pem.Decode(keyPEM)
	if keyBlock == nil {
		return fmt.Errorf("invalid CA key PEM at %s", keyPath)
	}
	key, err := x509.ParsePKCS1PrivateKey(keyBlock.Bytes)
	if err != nil {
		return err
	}

	cm.caCert = cert
	cm.caKey = key
	return nil
}

func (cm *certManager) generateCA(certPath, keyPath string) error {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return err
	}

	serial, err := rand.Int(rand.Reader, big.NewInt(1<<62))
	if err != nil {
		return err
	}

	tmpl := &x509.Certificate{
		SerialNumber: serial,
		Subject: pkix.Name{
			CommonName:   "freeweb-resolver local CA",
			Organization: []string{"freeweb-resolver"},
		},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().AddDate(10, 0, 0),
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign | x509.KeyUsageDigitalSignature,
		BasicConstraintsValid: true,
		IsCA:                  true,
	}

	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		return err
	}

	cert, err := x509.ParseCertificate(der)
	if err != nil {
		return err
	}

	certOut, err := os.Create(certPath)
	if err != nil {
		return err
	}
	defer certOut.Close()
	if err := pem.Encode(certOut, &pem.Block{Type: "CERTIFICATE", Bytes: der}); err != nil {
		return err
	}

	keyOut, err := os.OpenFile(keyPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		return err
	}
	defer keyOut.Close()
	if err := pem.Encode(keyOut, &pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)}); err != nil {
		return err
	}

	cm.caCert = cert
	cm.caKey = key
	return nil
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

// GetCertificate выдаёт (и кеширует) лист-сертификат на лету под запрошенное
// SNI-имя, подписанный нашим локальным CA.
func (cm *certManager) GetCertificate(hello *tls.ClientHelloInfo) (*tls.Certificate, error) {
	name := hello.ServerName
	if name == "" {
		name = "localhost"
	}

	cm.mu.Lock()
	if c, ok := cm.cache[name]; ok {
		cm.mu.Unlock()
		return c, nil
	}
	cm.mu.Unlock()

	leafKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, err
	}

	serial, err := rand.Int(rand.Reader, big.NewInt(1<<62))
	if err != nil {
		return nil, err
	}

	tmpl := &x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: name},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().AddDate(1, 0, 0),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	if ip := net.ParseIP(name); ip != nil {
		tmpl.IPAddresses = []net.IP{ip}
	} else {
		tmpl.DNSNames = []string{name}
	}

	der, err := x509.CreateCertificate(rand.Reader, tmpl, cm.caCert, &leafKey.PublicKey, cm.caKey)
	if err != nil {
		return nil, err
	}

	tlsCert := &tls.Certificate{
		Certificate: [][]byte{der, cm.caCert.Raw},
		PrivateKey:  leafKey,
	}

	cm.mu.Lock()
	cm.cache[name] = tlsCert
	cm.mu.Unlock()

	return tlsCert, nil
}

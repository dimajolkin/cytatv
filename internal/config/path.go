package config

import "path/filepath"

// Abs делает путь абсолютным относительно root. Пустая строка остаётся пустой.
func Abs(root, p string) string {
	if p == "" {
		return ""
	}
	if filepath.IsAbs(p) {
		return p
	}
	return filepath.Join(root, p)
}

// RequireNonEmpty возвращает ошибку если val пуст.
func RequireNonEmpty(name, val string) error {
	if val == "" {
		return errRequired(name)
	}
	return nil
}

type requiredError string

func (e requiredError) Error() string { return string(e) + " обязателен" }

func errRequired(name string) error { return requiredError(name) }

package config

// SystemAppSpec — приложение для system uid (обычно 1000), собираемое из repo.
type SystemAppSpec struct {
	ID          string `yaml:"id"`
	UID         int    `yaml:"uid"`
	APK         string `yaml:"apk"`
	Guest       string `yaml:"guest"`
	RemoveStock string `yaml:"remove_stock"`
	SkipBuild   bool   `yaml:"skip_build"`
	Pull        bool   `yaml:"pull"`
	Repo        string `yaml:"repo"`
	Ref         string `yaml:"ref"`
	SrcDir      string `yaml:"src_dir"`
	MakeTarget  string `yaml:"make_target"`
}

// AssetSpec — файл для pipeline (download / extract / seed).
type AssetSpec struct {
	Path       string       `yaml:"path"`
	URL        string       `yaml:"url"`
	From       string       `yaml:"from"` // локальный архив в assets_dir (после скачивания другого asset)
	Optional   bool         `yaml:"optional"`
	Chmod      string       `yaml:"chmod"`
	RequireARM bool         `yaml:"require_arm"`
	Extract    *ExtractSpec `yaml:"extract"`
}

// ExtractSpec unpacks an archive URL into path (+ optional siblings).
type ExtractSpec struct {
	Member string        `yaml:"member"`
	Also   []ExtractAlso `yaml:"also"`
}

// ExtractAlso extracts an extra member to another path under assets_dir.
type ExtractAlso struct {
	Member string `yaml:"member"`
	Path   string `yaml:"path"`
}

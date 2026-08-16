//go:build darwin || linux

package main

import (
	"fmt"
	"os/user"
	"strconv"
	"syscall"
)

// dropPrivileges отказывается от root после того, как привилегированные
// порты (443/53) уже забинжены — то есть после того, как единственная
// причина иметь root вообще исчерпана. Если процесс не запущен от root,
// это no-op: обычный (текущий) режим разработки на портах >1024 не требует
// root и не затрагивается.
// isElevated сообщает, работает ли процесс с правами root.
func isElevated() bool {
	return syscall.Geteuid() == 0
}

func dropPrivileges(username string) error {
	if syscall.Geteuid() != 0 {
		return nil
	}
	if username == "" {
		return fmt.Errorf("запущено от root, но --drop-to-user не задан: без этого флага процесс так и останется root")
	}

	u, err := user.Lookup(username)
	if err != nil {
		return fmt.Errorf("поиск пользователя %q: %w", username, err)
	}
	uid, err := strconv.Atoi(u.Uid)
	if err != nil {
		return fmt.Errorf("некорректный uid для %q: %w", username, err)
	}
	gid, err := strconv.Atoi(u.Gid)
	if err != nil {
		return fmt.Errorf("некорректный gid для %q: %w", username, err)
	}

	// Порядок важен: сначала дополнительные группы, потом gid, потом uid.
	// Если сбросить uid раньше групп — прав на смену групп уже не будет.
	if err := syscall.Setgroups([]int{gid}); err != nil {
		return fmt.Errorf("setgroups: %w", err)
	}
	if err := syscall.Setgid(gid); err != nil {
		return fmt.Errorf("setgid: %w", err)
	}
	if err := syscall.Setuid(uid); err != nil {
		return fmt.Errorf("setuid: %w", err)
	}

	// Контрольная проверка: убеждаемся, что вернуться в root уже физически
	// нельзя (setuid() у непривилегированного процесса на попытку стать
	// root обязан вернуть ошибку). Если вдруг не вернул — это значит сброс
	// не удался по-настоящему, и лучше упасть, чем продолжать думая, что
	// мы в безопасности.
	if err := syscall.Setuid(0); err == nil {
		return fmt.Errorf("КРИТИЧНО: сброс привилегий не подтверждён — процесс всё ещё может вернуться в root")
	}

	return nil
}

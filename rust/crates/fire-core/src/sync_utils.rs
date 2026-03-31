use std::sync::{RwLock, RwLockReadGuard, RwLockWriteGuard};

use tracing::warn;

pub(crate) fn read_rwlock<'a, T>(
    lock: &'a RwLock<T>,
    label: &'static str,
) -> RwLockReadGuard<'a, T> {
    match lock.read() {
        Ok(guard) => guard,
        Err(poisoned) => {
            warn!(lock = label, "recovering from poisoned RwLock read");
            poisoned.into_inner()
        }
    }
}

pub(crate) fn write_rwlock<'a, T>(
    lock: &'a RwLock<T>,
    label: &'static str,
) -> RwLockWriteGuard<'a, T> {
    match lock.write() {
        Ok(guard) => guard,
        Err(poisoned) => {
            warn!(lock = label, "recovering from poisoned RwLock write");
            poisoned.into_inner()
        }
    }
}

#[cfg(test)]
mod tests {
    use std::{
        panic::{self, AssertUnwindSafe},
        sync::RwLock,
    };

    use super::{read_rwlock, write_rwlock};

    #[test]
    fn recovers_from_poisoned_read_lock() {
        let lock = RwLock::new(41_u32);

        let _ = panic::catch_unwind(AssertUnwindSafe(|| {
            let _guard = lock.write().expect("write lock");
            panic!("poison lock");
        }));

        let guard = read_rwlock(&lock, "test-lock");
        assert_eq!(*guard, 41);
    }

    #[test]
    fn recovers_from_poisoned_write_lock() {
        let lock = RwLock::new(41_u32);

        let _ = panic::catch_unwind(AssertUnwindSafe(|| {
            let _guard = lock.write().expect("write lock");
            panic!("poison lock");
        }));

        {
            let mut guard = write_rwlock(&lock, "test-lock");
            *guard += 1;
        }

        assert_eq!(*read_rwlock(&lock, "test-lock"), 42);
    }
}

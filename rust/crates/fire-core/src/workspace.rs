use std::path::{Component, Path, PathBuf};

use crate::error::FireCoreError;

pub(crate) fn normalize_workspace_path(workspace_path: Option<String>) -> Option<PathBuf> {
    workspace_path.and_then(|value| {
        let trimmed = value.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(PathBuf::from(trimmed))
        }
    })
}

pub(crate) fn validate_workspace_relative_path(path: &Path) -> Result<(), FireCoreError> {
    if path.as_os_str().is_empty() || path.is_absolute() {
        return Err(FireCoreError::InvalidWorkspaceRelativePath {
            path: path.to_path_buf(),
        });
    }

    for component in path.components() {
        match component {
            Component::Normal(_) | Component::CurDir => {}
            Component::RootDir | Component::ParentDir | Component::Prefix(_) => {
                return Err(FireCoreError::InvalidWorkspaceRelativePath {
                    path: path.to_path_buf(),
                });
            }
        }
    }

    Ok(())
}

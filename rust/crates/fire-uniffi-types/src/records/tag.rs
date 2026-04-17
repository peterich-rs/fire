use fire_models::RequiredTagGroup;

#[derive(uniffi::Record, Debug, Clone)]
pub struct RequiredTagGroupState {
    pub name: String,
    pub min_count: u32,
}

impl From<RequiredTagGroup> for RequiredTagGroupState {
    fn from(value: RequiredTagGroup) -> Self {
        Self {
            name: value.name,
            min_count: value.min_count,
        }
    }
}

impl From<RequiredTagGroupState> for RequiredTagGroup {
    fn from(value: RequiredTagGroupState) -> Self {
        Self {
            name: value.name,
            min_count: value.min_count,
        }
    }
}

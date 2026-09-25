# 所有权、领域类型与错误边界

这份参考在你已经遇到所有权、类型或错误设计问题时使用。它不是“禁止清单”；每个选择都应该能回答数据为何要以这种形式存在。

## 所有权是资源生命周期

一个非 `Copy` 值在赋值、传参和返回时默认移动。移动不是复制失败，而是所有权从一个名字交给另一个名字；所有者离开作用域时，资源按 RAII 释放。

先从权限选择 API：

```rust
fn render(name: &str) -> String { format!("hello, {name}") }
fn normalize(name: &mut String) { *name = name.trim().to_owned(); }
fn enqueue(job: Job) { /* 保存或交给另一个 task */ }
```

`&T` 可以并存，`&mut T` 必须独占。这条规则把“谁能在何时修改”写进类型。遇到借用冲突时，优先缩小引用的活跃范围、先提取所需信息、或把互不相关的状态拆开；不要把整个对象包进一个锁来掩盖边界。

### 借用与拥有的常见边界

| 目的 | 优先选择 | 原因 |
| --- | --- | --- |
| 读取文本或序列 | `&str`、`&[T]` | 接受更多输入，且不承诺保存它 |
| 需要长期保存输入 | `String`、`Vec<T>`、`PathBuf` | 保存者拥有数据，生命周期不会传给调用者 |
| 递归数据或稳定堆地址 | `Box<T>` | 一个拥有者，堆分配是结构需要而非共享手段 |
| 单线程共享可变 | 先重划所有权；必要时 `Rc<RefCell<T>>` | 运行时检查借用，不能跨线程 |
| 跨线程/任务共享只读 | `Arc<T>` | 共享所有权，不自动提供可变性 |
| 跨线程/任务共享可变 | 单一所有者 + channel；必要时 `Arc<Mutex<T>>` / `Arc<RwLock<T>>` | 先选择状态协调模型，再选择同步原语 |

`Clone` 表示创建另一份值，通常比让结构体早早携带引用更容易保持边界清楚。它也可能很贵，因此应当让调用点说明意图。`Copy` 则意味着赋值隐式复制，只适用于复制语义自然、字段也都可复制的小值。不要为了少写 `.clone()` 而让一个有资源语义的类型变成 `Copy`。

## 类型应承担不变量

`struct` 用于同时存在的数据，`enum` 用于互斥的状态。先把状态空间列出来，再选类型：

```rust
enum Upload {
    Pending { bytes: Vec<u8> },
    InFlight { id: RequestId },
    Complete { location: Url },
    Failed { reason: UploadError },
}
```

这里不可能同时处在 `Pending` 和 `Complete`，因此不需要 `status: String` 加多个可空字段。反过来，若字段确实可独立存在，硬塞进 enum 会使正常更新变得别扭。

当 `String`、`u64` 或 `Duration` 的“底层一样”会导致领域混用时，使用 newtype：

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct UserId(u64);
```

newtype 应该表示边界、单位或权限，而不是为每个原始字段增加一层名字。为输入建立构造器或 `TryFrom`，把验证放在值进入领域模型的位置；这样内部代码不必重复检查。

### 字符串、路径和字节

- 拥有且可修改的 UTF-8 文本用 `String`；临时只读视图用 `&str`。
- 文件路径用 `Path`/`PathBuf`，操作系统字符串用 `OsStr`/`OsString`，C 边界用 `CStr`/`CString`。
- 网络帧、哈希和二进制协议优先建模为字节；不要假定它们是 UTF-8。
- Rust 不允许按整数索引 `str`，因为 UTF-8 是变长编码。需要按 Unicode scalar value 遍历用 `.chars()`；需要字节则明确使用 `.as_bytes()`。

`&String` 和 `&Vec<T>` 很少表达额外语义，通常应改为 `&str` 和 `&[T]`。若 API 必须保存调用者交来的数据，可用 `impl Into<String>` 等入口转换；不要在每一层都把泛型转换参数继续传播。

## Option、Result 与错误层次

`Option<T>` 只回答“值有没有”。`Result<T, E>` 还说明“为什么没有”。在这两者之间转换时，先确认是否愿意丢失错误信息。

```rust
fn read_config(path: &Path) -> Result<Config, ConfigError> {
    let text = std::fs::read_to_string(path).map_err(ConfigError::Read)?;
    toml::from_str(&text).map_err(ConfigError::Parse)
}
```

错误类型的粒度由谁要做决定决定：

- 可复用模块或库需要调用者恢复、重试或匹配错误时，保留结构化错误（常见为枚举）。
- 应用边界通常应附加动作相关的上下文，再记录或转换为 CLI/HTTP/UI 的错误。`anyhow` 很适合许多应用内部的“向上带上下文”，但不是所有项目必须采用的统一类型。
- `panic!`、`unwrap()`、`expect()` 留给已经由程序不变量保证的情况或测试。`expect` 信息应说明哪条不变量被违反，而不是重复“unwrap failed”。

不要在底层把错误格式化为字符串后再传递，那会失去来源、类型和可匹配性。若错误跨越抽象层，使用项目的转换约定、`From`、`map_err` 或 `#[from]` 保留因果关系。

## 生命周期是借用关系的一部分

生命周期不是延长对象寿命的开关，而是编译器验证引用不会悬垂的关系。函数返回引用时，返回值必须来自仍然有效的输入或 `self`；结构体存放引用时，生命周期自然成为它类型的一部分。

```rust
fn first_word(input: &str) -> &str {
    input.split_whitespace().next().unwrap_or("")
}
```

如果生命周期参数从一个小结构体一路蔓延到任务、缓存和公共 API，先确认是否把短暂借用误当成了长期数据。边界处持有 `String`、`Vec<T>` 或 `Arc<T>` 往往更直接；但零拷贝解析器、视图类型和高性能库的公共引用 API 也完全正当。选择取决于调用者需要什么，不是单纯为了躲开 `'a`。

## unsafe 是需要证明的边界

安全代码把内存规则交给编译器；unsafe 代码由作者承担证明义务。把 unsafe 缩在很小的模块或函数内，对外提供能维持不变量的安全 API，并在 unsafe 紧邻处写清楚：指针来自哪里、对齐与有效范围如何保证、别名规则如何满足、以及析构责任归谁。

不要把 `unsafe`、`from_utf8_unchecked`、`get_unchecked`、`static mut` 或伪造的 `'static` 当作借用检查器的逃生门。它们只能在已证明前置条件的狭窄场景下出现，并应同时接受专门的安全审查。

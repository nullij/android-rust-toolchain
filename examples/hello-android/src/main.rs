fn greeting() -> String {
    format!("Hello from Rust on Android ({})!", env!("TARGET_TRIPLE"))
}

fn main() {
    println!("{}", greeting());
}

#[cfg(test)]
mod tests {
    use super::greeting;

    #[test]
    fn reports_android_target() {
        let msg = greeting();
        assert!(msg.contains("android"));
        assert!(msg.contains(env!("TARGET_TRIPLE")));
    }
}
extern int android_link_probe(int fd);

int main(void) {
    return android_link_probe(-1);
}

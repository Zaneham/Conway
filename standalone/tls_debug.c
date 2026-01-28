// Debug TLS access
int main(void) {
    register long tp asm("tp");

    // Return TP value mod 256 so we can see it
    return (int)(tp & 0xFF);
}

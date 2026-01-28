// Test that reads TLS data and returns it
// If TLS is working, should return non-zero

int main(void) {
    // Access TLS via TP register
    register long tp asm("tp");
    
    // Read first 8 bytes from TLS block
    long *tls_data = (long *)tp;
    long first_value = *tls_data;
    
    // Return lower byte (should be 0x80 for 0x70680)
    return (int)(first_value & 0xFF);
}

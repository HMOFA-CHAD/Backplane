"""One postbuild parser regression; never builds or signs an application."""
from pathlib import Path
import importlib.util,os,unittest
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('producer',os.environ.get('BP_ANDROID_PRODUCER_SOURCE',str(ROOT/'scripts/build-android-artifacts.py')))
P=importlib.util.module_from_spec(spec);spec.loader.exec_module(P)
class Fingerprints(unittest.TestCase):
    def test_apksigner_certificate_is_not_public_key_and_wrong_signers_still_fail(self):
        cert='ef21acdb7d2de02106c29caf35eb73e704a152960e8113c8149eca1c305e906e'
        other='c3068a3c8c67ff6660b714b63d7ea503a6b9a8f55864ae2cdbb06a14c559c9c5'
        # Actual apksigner34 verbose line grammar (independently observed on retained APK).
        verbose=f'Number of signers: 1\nSigner #1 certificate SHA-256 digest: {cert}\nSigner #1 public key SHA-256 digest: {other}\n'
        self.assertEqual(P.certificate_hashes(verbose),{cert})
        self.assertEqual(P.certificate_hashes(f'Signer #1 public key SHA-256 digest: {other}\n'),set())
        self.assertEqual(P.certificate_hashes('Signer #1 certificate SHA-256 digest: '+other+'\n'),{other})
        self.assertNotEqual(P.certificate_hashes(verbose.replace(cert,other)),{cert})
        self.assertEqual(P.certificate_hashes(verbose+f'Signer #2 certificate SHA-256 digest: {other}\n'),{cert,other})
        self.assertNotEqual(P.certificate_hashes(verbose+f'Signer #2 certificate SHA-256 digest: {other}\n'),{cert})
        colon=':'.join(cert[i:i+2].upper() for i in range(0,64,2))
        self.assertEqual(P.certificate_hashes('Certificate fingerprints:\n\t SHA256: '+colon+'\n'),{cert})
        self.assertEqual(P.certificate_hashes('not-a-certificate SHA256: '+cert+'\n'),set())
if __name__=='__main__':unittest.main()

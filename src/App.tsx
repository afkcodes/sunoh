import Button from "./components/Button/Button";

function App() {
  return (
    <div className="flex justify-center items-center min-h-screen bg-bgPrimary text-textLight">
      <Button
        text="Hellos"
        onClick={() => {
          console.log("hello");
        }}
        variant="primary"
      />
    </div>
  );
}

export default App;
